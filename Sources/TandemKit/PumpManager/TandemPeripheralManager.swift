import CoreBluetooth

class TandemPeripheralManager: NSObject {
    private let logger = TandemLogger(category: "TandemPeripheralManager")
    private let fallbackPairingCode = "000000"

    private var peripheral: CBPeripheral
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
        _ peripheral: CBPeripheral,
        _ pumpManager: TandemPumpManager,
        _ connectCompletion: @escaping (Error?) -> Void
    ) {
        self.bluetoothManager = bluetoothManager
        self.peripheral = peripheral
        self.pumpManager = pumpManager
        _connectCompletion = connectCompletion

        authBuilder = JpakeAuthBuilder.initializeWithPairingCode(pumpManager.state.pumpState.pincode ?? fallbackPairingCode)
        super.init()

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
        guard let characteristic = getCharacteristic(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID
        ) else {
            logger
                .error(
                    "Could not find characteristic - Service: \(serviceUUID), Characteristic: \(characteristicUUID)"
                )
            return nil
        }

        logger.info("Reading characteristic: \(characteristic.uuid)")

        let readQ = TandemDispatchGroup()
        readQ.enter()
        readQueue = (readQ, characteristicUUID)

        defer {
            readQueue = nil
        }

        commandLock = TandemDispatchGroup()
        commandLock?.enter()
        peripheral.readValue(for: characteristic)

        return readQ.wait(timeout: .now() + .seconds(10))
    }

    func write(message: Message, expecting: Message.Type, maxChunkSize: Int? = nil) -> Message? {
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
        guard let characteristic = getCharacteristic(
            serviceUUID: ServiceUUID.PUMP_SERVICE,
            characteristicUUID: requestProps.characteristic
        ) else {
            logger
                .error(
                    "Could not find characteristic - Service: \(ServiceUUID.PUMP_SERVICE), Characteristic: \(requestProps.characteristic)"
                )
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

            peripheral.writeValue(item.build(), for: characteristic, type: .withResponse)
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
                characteristic: characteristic.uuid,
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
        guard let characteristic = getCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            return
        }

        commandLock = TandemDispatchGroup()
        commandLock?.enter()

        peripheral.setNotifyValue(true, for: characteristic)
        commandLock?.wait(timeout: .now() + .seconds(2))
    }

    private func getCharacteristic(serviceUUID: CBUUID, characteristicUUID: CBUUID) -> CBCharacteristic? {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            logger.error("Failed to find service: \(serviceUUID.uuidString)")
            return nil
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else {
            logger.error("Failed to find characteristic: \(characteristicUUID.uuidString)")
            return nil
        }

        return characteristic
    }
}

extension TandemPeripheralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error = error {
            logger.error("Failed to discoverServices: \(error.localizedDescription)")
            finishSetup(PumpCommError.errorResponse(context: "Failed to discoverServices: \(error.localizedDescription)"))
            return
        }

        self.peripheral = peripheral

        guard let pumpService = peripheral.services?.first(where: { $0.uuid == ServiceUUID.PUMP_SERVICE }) else {
            logger.error("No pump service found...")
            finishSetup(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.PUMP_SERVICE)"))
            return
        }
        peripheral.discoverCharacteristics(CharacteristicUUID.allPumpCharacteristics, for: pumpService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error = error {
            let message = "Failed to didDiscoverCharacteristics: \(error.localizedDescription)"
            logger.error(message)
            finishSetup(PumpCommError.errorResponse(context: message))
            return
        }

        self.peripheral = peripheral

        if service.uuid == ServiceUUID.PUMP_SERVICE {
            guard let deviceInfoService = peripheral.services?.first(where: { $0.uuid == ServiceUUID.DIS_SERVICE }) else {
                logger.error("No device info service found...")
                finishSetup(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.DIS_SERVICE)"))
                return
            }
            peripheral.discoverCharacteristics(CharacteristicUUID.allDeviceInfoCharacteristics, for: deviceInfoService)
            return
        }

        logger.info("Discovery completed! Services: \(peripheral.services?.map(\.uuid.uuidString) ?? [])")
        performInitialSetup()
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            logger.error("Received error in didUpdateValueFor: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            let char = characteristic.uuid.uuidString
            let service = characteristic.service?.uuid.uuidString ?? "No service"
            logger.warning("Empty data -> char: \(char), service: \(service)")
            return
        }

        if let (readQueue, readCharacteristic) = readQueue,
           readCharacteristic == characteristic.uuid
        {
            readQueue.leave(Data(data))
            return
        }

        // The history log characteristic only ever carries unsolicited HistoryLogStreamResponse
        // notifications, so route it before the write-queue check: continuation packets of a
        // multi-packet stream message carry cargo at data[2] that could otherwise alias a
        // pending write's expected opcode.
        if characteristic.uuid == CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS {
            handleHistoryLogStreamPacket(data)
            return
        }

        if let (writeQueue, writeOpCode) = writeQueue, data[2] == writeOpCode {
            writeQueue.leave(Data(data))
            return
        }

        if characteristic.uuid == CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS {
            let events = QualifyingEvent.fromRawBytes(data)
            guard !events.isEmpty else {
                logger.info("Received empty qualifying events")
                return
            }

            pumpManager.handleQualifyingEvents(events: events) {
                // Acknowledge qualifying events
                self.peripheral.writeValue(Data([0, 0, 0, 0]), for: characteristic, type: .withResponse)
            }
            return
        }

        if characteristic.uuid == FillTubingStateStreamResponse.props.characteristic,
           data[2] == FillTubingStateStreamResponse.props.opCode
        {
            let response = FillTubingStateStreamResponse(cargo: Data(data.dropFirst(5)))
            pumpManager.fillTubingStateStream.send(response)
            return
        }

        if characteristic.uuid == FillCannulaStateStreamResponse.props.characteristic,
           data[2] == FillCannulaStateStreamResponse.props.opCode
        {
            let response = FillCannulaStateStreamResponse(cargo: Data(data.dropFirst(5)))
            pumpManager.fillCannulaStateStream.send(response)
            return
        }

        if characteristic.uuid == EnterChangeCartridgeModeStateStreamResponse.props.characteristic,
           data[2] == EnterChangeCartridgeModeStateStreamResponse.props.opCode
        {
            let response = EnterChangeCartridgeModeStateStreamResponse(cargo: Data(data.dropFirst(5)))
            pumpManager.changeCartridgeStateStream.send(response)
            return
        }

        // DetectingCartridgeStateStreamResponse and LoadCartridgeStateStreamResponse share opcode
        // -29 and are told apart by total packet length, the same split ControlStreamMessages makes.
        if characteristic.uuid == DetectingCartridgeStateStreamResponse.props.characteristic,
           data[2] == DetectingCartridgeStateStreamResponse.props.opCode
        {
            if data.count >= 26 {
                let response = DetectingCartridgeStateStreamResponse(cargo: Data(data.dropFirst(5)))
                pumpManager.detectingCartridgeStateStream.send(response)
            } else {
                let response = LoadCartridgeStateStreamResponse(cargo: Data(data.dropFirst(5)))
                logger.info("Received load cartridge state: \(response.description)")
            }
            return
        }

        if characteristic.uuid == CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
           data[2] == ErrorResponse.props.opCode
        {
            let response = ErrorResponse(cargo: Data(data.dropFirst(5)))
            logger.error("Received error message: \(response.description)")
            return
        }

        logger.warning("Not handler for message - data: \(data.hexadecimalString) characteristic: \(characteristic.uuid)")
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
        pumpManager.historyLogStream.send(message)
    }

    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: (any Error)?) {
        if let error {
            logger.error("Received error after write characteristic: \(error.localizedDescription)")
        }

        commandLock?.leave(Data())
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor _: CBCharacteristic, error: (any Error)?) {
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
            #if canImport(ObjectiveC)
            if let central = pumpManager.bluetooth.manager {
                let selector = NSSelectorFromString("setDesiredConnectionLatency:forPeripheral:")
                if central.responds(to: selector) {
                    let latencyValue = NSNumber(value: 0) // CBPeripheralConnectionLatency.low
                    central.perform(selector, with: latencyValue, with: peripheral)
                    logger.info("connection priority set -> CBPeripheralConnectionLatency.low")
                } else {
                    logger.warning("central manager does not support connection latency adjustment")
                }
            }
            #endif

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

                while let (request, expectedResponse) = authBuilder.nextRequest() {
                    guard let response = write(message: request, expecting: expectedResponse) else {
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

            guard let response = write(
                message: TimeSinceResetRequest(),
                expecting: TimeSinceResetResponse.self
            ) as? TimeSinceResetResponse else {
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
