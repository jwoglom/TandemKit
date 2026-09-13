import CoreBluetooth

class TandemPeripheralManager {
    private let logger = TandemLogger(category: "TandemPeripheralManager")
    private let fallbackPairingCode = "000000"

    private let peripheral: PumpPeripheral
    private let pumpManager: TandemPumpManager
    private let bluetoothManager: TandemBluetoothManager
    // Claimed exactly once by finishSetup, which may be called from the CB delegate queue (a
    // discovery error) or from the setup task on a global queue (every performInitialSetup exit),
    // so the take-and-clear happens under queueLock.
    private var _connectCompletion: ((Error?) -> Void)?

    // These three handoff slots are written on the command thread (write/read/startNotify) and read
    // on the CB delegate queue (didUpdateValueFor / didWriteValueFor / cancelPendingOperations).
    // They are guarded by queueLock so the cross-thread reference access can't tear (the previous
    // unsynchronized access was undefined behavior). The lock only protects the get/set of the
    // reference itself — blocking waits on the referenced group happen outside the lock.
    private let queueLock = NSLock()
    private var _readQueue: (TandemDispatchGroup, CBUUID)?
    private var _writeQueue: (TandemDispatchGroup, UInt8)?
    private var _commandLock: TandemDispatchGroup?

    private var readQueue: (TandemDispatchGroup, CBUUID)? {
        get { queueLock.lock()
            defer { queueLock.unlock() }
            return _readQueue }
        set { queueLock.lock()
            _readQueue = newValue
            queueLock.unlock() }
    }

    private var writeQueue: (TandemDispatchGroup, UInt8)? {
        get { queueLock.lock()
            defer { queueLock.unlock() }
            return _writeQueue }
        set { queueLock.lock()
            _writeQueue = newValue
            queueLock.unlock() }
    }

    private var commandLock: TandemDispatchGroup? {
        get { queueLock.lock()
            defer { queueLock.unlock() }
            return _commandLock }
        set { queueLock.lock()
            _commandLock = newValue
            queueLock.unlock() }
    }

    private let writeSemaphore = DispatchSemaphore(value: 1)
    private var currentTxId: UInt8 = 0

    // Sized for the slowest command, not the typical one: EnterChangeCartridgeMode doesn't respond
    // until the cartridge is safe to remove, which takes 5-20s. Timing out early reports a failure
    // for a command still in progress, inviting a re-send of an insulin-affecting request.
    private static let responseTimeout: DispatchTimeInterval = .seconds(30)
    // Above responseTimeout, so a caller queued behind one slow write waits it out.
    private static let writeLockTimeout: DispatchTimeInterval = .seconds(45)

    private var authBuilder: JpakeAuthBuilder

    // Reassembles the (possibly multi-packet) unsolicited HistoryLogStreamResponse
    // notifications that arrive on the history log characteristic. Only touched on the
    // CB delegate queue (didUpdateValueFor / cancelPendingOperations callers' queue).
    private var historyLogStreamAccumulator: ResponseMessage?

    init(
        _ bluetoothManager: TandemBluetoothManager,
        _ peripheral: PumpPeripheral,
        _ pumpManager: TandemPumpManager,
        _ connectCompletion: @escaping (Error?) -> Void
    ) {
        self.bluetoothManager = bluetoothManager
        self.peripheral = peripheral
        self.pumpManager = pumpManager
        _connectCompletion = connectCompletion

        authBuilder = JpakeAuthBuilder.initializeWithPairingCode(pumpManager.state.pumpState.pincode ?? fallbackPairingCode)

        peripheral.delegate = self
    }

    /// Ends this connection attempt as a failure. Only disconnects while this peripheral manager
    /// is still the live one: a setup task orphaned by a mid-handshake drop keeps running for
    /// seconds, and by then the auto-reconnect may own an authenticated session it must not kill.
    private func failSetup(_ error: Error) {
        if bluetoothManager.isCurrentPeripheralManager(self) {
            bluetoothManager.disconnect()
        } else {
            logger.info("Setup failed on a superseded connection; not disconnecting the live session")
        }

        finishSetup(error)
    }

    /// Reports this attempt's outcome exactly once; several discovery callbacks can each fail.
    private func finishSetup(_ error: Error?) {
        queueLock.lock()
        let completion = _connectCompletion
        _connectCompletion = nil
        queueLock.unlock()

        completion?(error)
    }

    func read(serviceUUID: CBUUID, characteristicUUID: CBUUID) -> Data? {
        guard hasCharacteristic(characteristicUUID, in: serviceUUID) else {
            return nil
        }

        logger.info("Reading characteristic: \(characteristicUUID)")

        let readQ = TandemDispatchGroup()
        readQ.enter()
        readQueue = (readQ, characteristicUUID)

        defer {
            readQueue = nil
        }

        commandLock = TandemDispatchGroup()
        commandLock?.enter()
        peripheral.readValue(for: characteristicUUID, in: serviceUUID)

        return readQ.wait(timeout: .now() + .seconds(10))
    }

    func write<R: PumpRequest>(_ request: R, maxChunkSize: Int? = nil) -> R.Response? {
        writeUntyped(request, expecting: R.Response.self, maxChunkSize: maxChunkSize) as? R.Response
    }

    /// Escape hatch for callers that only know their message at runtime — the debug tools, which
    /// pick one by name out of `MessageRegistry`. Everything else goes through the generic `write`,
    /// which takes the reply type from the request itself.
    func writeUntyped(_ message: any Message, expecting: any Message.Type, maxChunkSize: Int? = nil) -> (any Message)? {
        guard expecting.props.type == .Response else {
            logger.error("Cannot write \(type(of: message)): \(expecting) is not a response type")
            return nil
        }

        // Pump I/O is already serialized by TandemBluetoothManager.commandQueue, so this lock
        // should never actually contend. It is kept purely as defense-in-depth, and the acquire
        // is bounded so that even an unexpected off-pipeline caller can never deadlock here (the
        // unbounded wait that used to live here was a primary cause of the connection hang).
        // On the success path the matching signal() is registered immediately via defer; on the
        // timeout path we never acquired the lock, so we must not signal.
        guard writeSemaphore.wait(timeout: .now() + Self.writeLockTimeout) == .success else {
            logger.error("Timed out acquiring write lock; pump I/O unexpectedly contended")
            return nil
        }
        defer { writeSemaphore.signal() }

        let requestProps = type(of: message).props
        let characteristic = requestProps.characteristic
        guard hasCharacteristic(characteristic, in: ServiceUUID.PUMP_SERVICE) else {
            return nil
        }

        var writeQ = TandemDispatchGroup()
        writeQ.enter()
        writeQueue = (writeQ, expecting.props.opCode)

        defer {
            writeQueue = nil
        }

        var response = ResponseMessage()
        var authKey = Data()
        if requestProps.signed {
            authKey = pumpManager.state.pumpState.getAuthKey()
        }

        logger.info("Writing message: \(message.description)")
        for item in Packetize.parse(
            message: message,
            authenticationKey: authKey,
            txId: currentTxId,
            timeSinceReset: pumpManager.state.pumpState.timeSinceReset,
            maxChunkSize: maxChunkSize
        ) {
            commandLock = TandemDispatchGroup()
            commandLock?.enter()

            peripheral.writeValue(item.build(), for: characteristic, in: ServiceUUID.PUMP_SERVICE)
            commandLock?.wait(timeout: .now() + .seconds(2))
        }

        currentTxId = currentTxId &+ 1
        while response.needsMorePacket {
            // Wait for result from pump
            let outcome = writeQ.waitForOutcome(timeout: .now() + Self.responseTimeout)
            guard case let .completed(result) = outcome else {
                if outcome == .cancelled {
                    // Torn down by cancelPendingOperations, not the pump going quiet.
                    logger.error("Write cancelled before a response arrived; link or Bluetooth went away")
                } else {
                    logger.error("Timeout hit, no response from pump...")
                }
                return nil
            }

            BTResponseParser.parse(
                data: result,
                characteristic: characteristic,
                authKey: authKey,
                response: &response
            )

            if response.needsMorePacket {
                writeQ = TandemDispatchGroup()
                writeQ.enter()
                writeQueue = (writeQ, expecting.props.opCode)

                logger.info("Waiting for more data...")
            }
        }

        logger.info("Received message: \(response.message?.description ?? "nil")")
        return response.message
    }

    /// Cancels any in-flight read/write/notify command waits so a thread blocked
    /// inside `read`/`write` returns promptly (with `nil`), allowing its calling
    /// closure to finish and release the connection/write locks. Invoked when the
    /// peripheral disconnects or Bluetooth is no longer powered on, where the
    /// matching BLE callbacks that would normally `leave()` these groups will
    /// never arrive. `cancel()` is idempotent, so this is safe to call at any
    /// time and regardless of whether an operation is actually in flight.
    func cancelPendingOperations() {
        logger.info("Cancelling pending operations")
        commandLock?.cancel()
        writeQueue?.0.cancel()
        readQueue?.0.cancel()
        // A partially assembled stream message can never complete once the connection drops.
        historyLogStreamAccumulator = nil
    }

    func startNotify(service serviceUUID: CBUUID, characteristic characteristicUUID: CBUUID) {
        guard hasCharacteristic(characteristicUUID, in: serviceUUID) else {
            return
        }

        commandLock = TandemDispatchGroup()
        commandLock?.enter()

        peripheral.setNotifyValue(true, for: characteristicUUID, in: serviceUUID)
        commandLock?.wait(timeout: .now() + .seconds(2))
    }

    private func hasCharacteristic(_ characteristicUUID: CBUUID, in serviceUUID: CBUUID) -> Bool {
        guard peripheral.hasCharacteristic(characteristicUUID, in: serviceUUID) else {
            logger
                .error("Could not find characteristic - Service: \(serviceUUID), Characteristic: \(characteristicUUID)")
            return false
        }
        return true
    }
}

extension TandemPeripheralManager: PumpPeripheralDelegate {
    func peripheral(_ peripheral: PumpPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Failed to discoverServices: \(error.localizedDescription)")
            finishSetup(PumpCommError.errorResponse(context: "Failed to discoverServices: \(error.localizedDescription)"))
            return
        }

        guard peripheral.discoveredServices.contains(ServiceUUID.PUMP_SERVICE) else {
            logger.error("No pump service found...")
            finishSetup(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.PUMP_SERVICE)"))
            return
        }
        peripheral.discoverCharacteristics(CharacteristicUUID.allPumpCharacteristics, for: ServiceUUID.PUMP_SERVICE)
    }

    func peripheral(_ peripheral: PumpPeripheral, didDiscoverCharacteristicsFor service: CBUUID, error: Error?) {
        if let error = error {
            let message = "Failed to didDiscoverCharacteristics: \(error.localizedDescription)"
            logger.error(message)
            finishSetup(PumpCommError.errorResponse(context: message))
            return
        }

        if service == ServiceUUID.PUMP_SERVICE {
            guard peripheral.discoveredServices.contains(ServiceUUID.DIS_SERVICE) else {
                logger.error("No device info service found...")
                finishSetup(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.DIS_SERVICE)"))
                return
            }
            peripheral.discoverCharacteristics(
                CharacteristicUUID.allDeviceInfoCharacteristics,
                for: ServiceUUID.DIS_SERVICE
            )
            return
        }

        logger.info("Discovery completed! Services: \(peripheral.discoveredServices.map(\.uuidString))")
        performInitialSetup()
    }

    func peripheral(_: PumpPeripheral, didUpdateValueFor characteristic: CBUUID, value: Data?, error: Error?) {
        if let error {
            logger.error("Received error in didUpdateValueFor: \(error.localizedDescription)")
            return
        }

        guard let data = value else {
            logger.warning("Empty data -> char: \(characteristic.uuidString)")
            return
        }

        if let (readQueue, readCharacteristic) = readQueue,
           readCharacteristic == characteristic
        {
            readQueue.leave(Data(data))
            return
        }

        // The history log characteristic only ever carries unsolicited HistoryLogStreamResponse
        // notifications, so route it before the write-queue check: continuation packets of a
        // multi-packet stream message carry cargo at data[2] that could otherwise alias a
        // pending write's expected opcode.
        if characteristic == CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS {
            handleHistoryLogStreamPacket(data)
            return
        }

        if let (writeQueue, writeOpCode) = writeQueue, data[2] == writeOpCode {
            writeQueue.leave(Data(data))
            return
        }

        if characteristic == CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS {
            let events = QualifyingEvent.fromRawBytes(data)
            guard !events.isEmpty else {
                logger.info("Received empty qualifying events")
                return
            }

            pumpManager.handleQualifyingEvents(events: events) {
                // Acknowledge qualifying events
                self.peripheral.writeValue(Data([0, 0, 0, 0]), for: characteristic, in: ServiceUUID.PUMP_SERVICE)
            }
            return
        }

        if characteristic == FillTubingStateStreamResponse.props.characteristic,
           data[2] == FillTubingStateStreamResponse.props.opCode
        {
            let response = FillTubingStateStreamResponse(cargo: Data(data.dropFirst(5)))
            logger.info("Received stream message: \(response.description)")
            pumpManager.fillTubingStateStream.send(response)
            return
        }

        if characteristic == FillCannulaStateStreamResponse.props.characteristic,
           data[2] == FillCannulaStateStreamResponse.props.opCode
        {
            let response = FillCannulaStateStreamResponse(cargo: Data(data.dropFirst(5)))
            logger.info("Received stream message: \(response.description)")
            pumpManager.fillCannulaStateStream.send(response)
            return
        }

        if characteristic == EnterChangeCartridgeModeStateStreamResponse.props.characteristic,
           data[2] == EnterChangeCartridgeModeStateStreamResponse.props.opCode
        {
            let response = EnterChangeCartridgeModeStateStreamResponse(cargo: Data(data.dropFirst(5)))
            logger.info("Received stream message: \(response.description)")
            pumpManager.changeCartridgeStateStream.send(response)
            return
        }

        // DetectingCartridgeStateStreamResponse and LoadCartridgeStateStreamResponse share opcode
        // -29 and are told apart by total packet length, the same split ControlStreamMessages makes.
        if characteristic == DetectingCartridgeStateStreamResponse.props.characteristic,
           data[2] == DetectingCartridgeStateStreamResponse.props.opCode
        {
            if data.count >= 26 {
                let response = DetectingCartridgeStateStreamResponse(cargo: Data(data.dropFirst(5)))
                logger.info("Received stream message: \(response.description)")
                pumpManager.detectingCartridgeStateStream.send(response)
            } else {
                let response = LoadCartridgeStateStreamResponse(cargo: Data(data.dropFirst(5)))
                logger.info("Received stream message: \(response.description)")
            }
            return
        }

        // ExitFillTubingModeStateStreamResponse and PumpingStateStreamResponse are the same wire
        // message under opcode -23, told apart only by payload size. The packet header carries it
        // at data[4] as the cargo size plus the 24-byte trailer every signed message has.
        if characteristic == ExitFillTubingModeStateStreamResponse.props.characteristic,
           data[2] == ExitFillTubingModeStateStreamResponse.props.opCode,
           data.count > 5
        {
            let cargo = Data(data.dropFirst(5))
            if Int(data[4]) == Int(PumpingStateStreamResponse.props.size) + 24 {
                let response = PumpingStateStreamResponse(cargo: cargo)
                logger.info("Received stream message: \(response.description)")
                pumpManager.pumpingStateStream.send(response)
            } else {
                let response = ExitFillTubingModeStateStreamResponse(cargo: cargo)
                logger.info("Received stream message: \(response.description)")
                pumpManager.exitFillTubingModeStateStream.send(response)
            }
            return
        }

        if characteristic == CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
           data[2] == ErrorResponse.props.opCode
        {
            let response = ErrorResponse(cargo: Data(data.dropFirst(5)))
            logger.error("Received error message: \(response.description)")
            return
        }

        logger.warning("Not handler for message - data: \(data.hexadecimalString) characteristic: \(characteristic)")
    }

    /// Accumulates history log stream packets until a full message is assembled, then
    /// publishes the parsed HistoryLogStreamResponse to the pump manager's stream.
    private func handleHistoryLogStreamPacket(_ data: Data) {
        var response = historyLogStreamAccumulator ?? ResponseMessage()
        BTResponseParser.parse(
            data: data,
            characteristic: CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS,
            authKey: nil,
            response: &response
        )

        if response.needsMorePacket {
            historyLogStreamAccumulator = response
            return
        }

        historyLogStreamAccumulator = nil
        guard let message = response.message as? HistoryLogStreamResponse else {
            logger.warning("Unparseable history log stream message: \(data.hexadecimalString)")
            return
        }
        logger.info("Received stream message: \(message.description)")
        pumpManager.historyLogStream.send(message)
    }

    func peripheral(_: PumpPeripheral, didWriteValueFor _: CBUUID, error: Error?) {
        if let error {
            logger.error("Received error after write characteristic: \(error.localizedDescription)")
        }

        commandLock?.leave(Data())
    }

    func peripheral(_: PumpPeripheral, didUpdateNotificationStateFor _: CBUUID, error: Error?) {
        if let error {
            logger.error("Received error after didUpdateNotificationStateFor: \(error.localizedDescription)")
        }

        commandLock?.leave(Data())
    }
}

extension TandemPeripheralManager {
    /// Runs off the command queue and writes to the peripheral directly, bypassing
    /// TandemBluetoothManager.write and its queue precondition. That is safe only because this runs
    /// during connection setup, while connectIfNeeded is parked in its wait on the command queue —
    /// no other command can be in flight. Keep it that way: setup must stay confined to the window
    /// before connectIfNeeded returns.
    func performInitialSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            defer {
                JpakeAuthBuilder.clearInstance()
            }

            // Step 1: Requesting high priority. Optimisation only.
            if let central = pumpManager.bluetooth.central as? PumpCentralLatencyControl {
                central.requestLowLatency(for: peripheral)
            }

            // Step 2: Read model & manufacturer
            guard let _ = read(
                serviceUUID: ServiceUUID.DIS_SERVICE,
                characteristicUUID: CharacteristicUUID.DIS_MANUFACTURER_NAME
            ) else {
                logger.error("Failed to read Manufacturer...")
                failSetup(PumpCommError.noResponse)
                return
            }

            guard let _ = read(serviceUUID: ServiceUUID.DIS_SERVICE, characteristicUUID: CharacteristicUUID.DIS_MODEL_NUMBER)
            else {
                logger.error("Failed to read model number...")
                failSetup(PumpCommError.noResponse)
                return
            }

            // Step 3: Start notify
            for (service, characteristic) in CharacteristicUUID.notificationCharacteristics {
                startNotify(service: service, characteristic: characteristic)
            }

            logger.debug("Notify completed!")

            // Step 4: Authenticate
            Thread.sleep(forTimeInterval: .milliseconds(500))

            if !authBuilder.done() {
                logger.info("Doing jpake pairing")
                JpakeAuthBuilder.clearInstance()

                let pincode = pumpManager.state.pumpState.pincode ?? self.fallbackPairingCode
                if let derivedSecret = pumpManager.state.pumpState.derivedSecret {
                    authBuilder = JpakeAuthBuilder.initializeWithDerivedSecret(pairingCode: pincode, derivedSecret: derivedSecret)
                } else {
                    authBuilder = JpakeAuthBuilder.initializeWithPairingCode(pincode)
                }

                while let request = authBuilder.nextRequest() {
                    guard let response = write(request) else {
                        logger.error("Failed to send JPAKE confirm")
                        failSetup(PumpCommError.noResponse)
                        return
                    }

                    authBuilder.processResponse(response)
                }

                guard authBuilder.done(), let secret = authBuilder.getDerivedSecret(),
                      let serverNonce = authBuilder.getServerNonce()
                else {
                    let done = "done=\(authBuilder.done()),"
                    let invalid = "invalid=\(authBuilder.invalid()),"
                    let derived = "derivedSecret=\(authBuilder.getDerivedSecret() != nil),"
                    let secret = "serverNonce=\(authBuilder.getServerNonce() != nil)"
                    logger.error("JPAKE failed: \(done) \(invalid) \(derived) \(secret)")

                    // Must complete the connect attempt, otherwise connectIfNeeded blocks for the
                    // full connectTimeout and stalls every queued command behind it.
                    failSetup(PumpCommError.noResponse)
                    return
                }

                pumpManager.state.pumpState.serverNonce = serverNonce
                pumpManager.state.pumpState.derivedSecret = secret
                pumpManager.state.pumpState.peripheralUuid = peripheral.identifier.uuidString
            }

            guard let response = write(TimeSinceResetRequest()) else {
                self.logger.error("Failed to send TimeSinceResetRequest...")
                failSetup(PumpCommError.noResponse)
                return
            }

            pumpManager.state.isConnected = true
            pumpManager.state.pumpState.timeSinceReset = response.pumpTimeSinceReset
            pumpManager.notifyDelegateStateUpdated()

            logger.info("Connected to pump!")
            finishSetup(nil)
        }
    }
}
