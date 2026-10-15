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
    // on the CB delegate queue (didUpdateValueFor / didWriteValueFor / linkWentDown).
    // They are guarded by queueLock so the cross-thread reference access can't tear (the previous
    // unsynchronized access was undefined behavior). The lock only protects the get/set of the
    // reference itself — blocking waits on the referenced group happen outside the lock.
    private let queueLock = NSLock()
    private var _readQueue: (TandemDispatchGroup, CBUUID)?
    private var _writeQueue: PendingWrite?
    private var _commandLock: TandemDispatchGroup?
    private var _isSessionEstablished = false
    private var _eventsBeforeSession: Set<QualifyingEvent> = []
    private var _linkLoss: LinkLoss?

    /// Why the link under this peripheral manager went away. Each connection has its own, so it is
    /// set once and stays.
    enum LinkLoss: Equatable {
        /// `CBError.connectionTimeout`: the phone stopped hearing the pump, as in a weak-signal
        /// stretch. A pump that ends the link sends a terminate, reported as `peripheralDisconnected`.
        case radio
        /// Bluetooth on the phone went off or is resetting.
        case bluetooth
        /// Any other drop, the pump's own and one the driver asked for among them.
        case other

        init(disconnectError error: Error?) {
            self = (error as? CBError)?.code == .connectionTimeout ? .radio : .other
        }
    }

    /// Why a write has no response to return.
    enum WriteFailure: Error, Equatable {
        /// Never reached the pump: the link was already gone, or the characteristic was not found.
        case notSent
        /// The link went away while the answer was awaited.
        case linkLost(LinkLoss)
        /// Timed out with the link up, refused, or answered with nothing that parses.
        case unanswered

        /// Whether a JPAKE round that failed this way counts towards `jpakeFailureLimit`: only what
        /// the pump may have done, so not a write it never got nor a link lost on the phone's side.
        var countsAsJpakeFailure: Bool {
            switch self {
            case .notSent: false
            case let .linkLost(loss): loss == .other
            case .unanswered: true
            }
        }
    }

    /// True once setup has authenticated this connection and its first request was answered.
    var isSessionEstablished: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _isSessionEstablished
    }

    var linkLoss: LinkLoss? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _linkLoss
    }

    /// Makes an operation the one in flight, unless the link is already gone. Atomic with
    /// `linkWentDown`, so an operation is either refused here or cancelled there.
    private func begin(_ install: () -> Void) -> Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard _linkLoss == nil else {
            return false
        }
        install()
        return true
    }

    private var readQueue: (TandemDispatchGroup, CBUUID)? {
        get { queueLock.lock()
            defer { queueLock.unlock() }
            return _readQueue }
        set { queueLock.lock()
            _readQueue = newValue
            queueLock.unlock() }
    }

    /// The write whose answer is awaited, reassembled here on the notification path. The answer
    /// comes on the request's characteristic under the request's txId and starts with the response
    /// opcode; a refusal is an ErrorResponse under that txId, on CURRENT_STATUS or the request's
    /// characteristic. Every other piece is left to the caller, another app's response on the link
    /// the phone shares included, as is a late answer to an earlier write.
    private final class PendingWrite {
        enum Taken {
            case needsMore
            /// nil when the answer does not decode as the response type.
            case answered(Message?)
            case refused(ErrorResponse)
            /// A message under the txId arrived whole but is not the answer; the write still waits.
            case discarded(String)
        }

        let group: TandemDispatchGroup
        let requestOpCode: UInt8
        let opCode: UInt8
        let characteristic: CBUUID
        let txId: UInt8
        private let lock = NSLock()
        private var assembler = PacketAssembler()
        private var assemblingOn: CBUUID?
        private var isFinished = false
        private var _message: Message?
        private var _refusal: ErrorResponse?

        init(group: TandemDispatchGroup, requestOpCode: UInt8, opCode: UInt8, characteristic: CBUUID, txId: UInt8) {
            self.group = group
            self.requestOpCode = requestOpCode
            self.opCode = opCode
            self.characteristic = characteristic
            self.txId = txId
        }

        var refusal: ErrorResponse? {
            lock.lock()
            defer { lock.unlock() }
            return _refusal
        }

        var message: Message? {
            lock.lock()
            defer { lock.unlock() }
            return _message
        }

        /// nil when `data` is not a piece of the answer.
        func take(_ data: Data, on characteristic: CBUUID) -> Taken? {
            lock.lock()
            defer { lock.unlock() }
            guard !isFinished else { return nil }
            if assembler.isEmpty {
                guard let start = PacketAssembler.start(of: data), start.txId == txId,
                      accepts(start.opCode, on: characteristic)
                else {
                    return nil
                }
                assemblingOn = characteristic
            } else {
                guard characteristic == assemblingOn, assembler.continues(with: data) else { return nil }
            }

            switch assembler.take(data) {
            case .notPart: return nil
            case .needsMore: return .needsMore
            case let .corrupt(reason): return .discarded(reason)
            case let .complete(message): return finish(message)
            }
        }

        private func accepts(_ opCode: UInt8, on characteristic: CBUUID) -> Bool {
            if opCode == self.opCode {
                return characteristic == self.characteristic
            }
            return opCode == ErrorResponse.props.opCode
                && (characteristic == self.characteristic || characteristic == CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS)
        }

        private func finish(_ message: AssembledMessage) -> Taken {
            if message.opCode != opCode {
                guard message.payloadLength >= 2 else { return .discarded("ErrorResponse with no request in it") }
                let refusal = ErrorResponse(cargo: message.cargo)
                guard refusal.requestCodeId == Int(requestOpCode) else {
                    return .discarded("ErrorResponse refusing opcode \(refusal.requestCodeId)")
                }
                _refusal = refusal
                isFinished = true
                group.leave(Data())
                return .refused(refusal)
            }

            let decoded = BTResponseParser.decode(message, characteristic: characteristic)
            _message = decoded
            isFinished = true
            group.leave(Data())
            return .answered(decoded)
        }
    }

    private var writeQueue: PendingWrite? {
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
    private static var responseTimeout: DispatchTimeInterval {
        #if TANDEMKIT_VIRTUAL_PUMP
        if let override = VirtualPump.responseTimeout { return override }
        #endif
        return .seconds(30)
    }
    // Above responseTimeout, so a caller queued behind one slow write waits it out.
    private static let writeLockTimeout: DispatchTimeInterval = .seconds(45)

    private var authBuilder: JpakeAuthBuilder

    // Only touched on the CB delegate queue (didUpdateValueFor / linkWentDown callers' queue).
    private var historyLogStream = PacketAssembler()
    private var controlStream = PacketAssembler()
    private var unsolicited: [CBUUID: PacketAssembler] = [:]

    // Under queueLock: a write that times out records itself on the command thread.
    private var _unsolicitedLog = UnsolicitedNotificationLog()

    private static let requestCharacteristics: Set<CBUUID> = [
        CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        CharacteristicUUID.CONTROL_CHARACTERISTICS,
        CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS,
    ]

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
        var deferredEvents: Set<QualifyingEvent> = []
        if error == nil {
            _isSessionEstablished = true
            swap(&deferredEvents, &_eventsBeforeSession)
        }
        queueLock.unlock()

        completion?(error)

        if !deferredEvents.isEmpty {
            logger.info("Handling qualifying events that arrived during setup: \(deferredEvents)")
            pumpManager.handleQualifyingEvents(events: deferredEvents) {}
        }
    }

    /// Holds qualifying events until setup finishes. Fetching on them mid-handshake sends a status
    /// request the pump does not answer on an unauthenticated link, and that request holds the
    /// write lane for the whole response timeout while JPAKE waits behind it.
    private func deferUntilSessionEstablished(_ events: Set<QualifyingEvent>) -> Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard !_isSessionEstablished else { return false }
        _eventsBeforeSession.formUnion(events)
        return true
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
        guard begin({ _readQueue = (readQ, characteristicUUID) }) else {
            logger.error("Link is gone; not reading \(characteristicUUID)")
            return nil
        }

        defer {
            readQueue = nil
        }

        commandLock = TandemDispatchGroup()
        commandLock?.enter()
        peripheral.readValue(for: characteristic)

        return readQ.wait(timeout: .seconds(10))
    }

    func write<R: PumpRequest>(_ request: R, maxChunkSize: Int? = nil) -> R.Response? {
        writeUntyped(request, expecting: R.Response.self, maxChunkSize: maxChunkSize) as? R.Response
    }

    /// Escape hatch for callers that only know their message at runtime — the debug tools, which
    /// pick one by name out of `MessageRegistry`. Everything else goes through the generic `write`,
    /// which takes the reply type from the request itself.
    func writeUntyped(_ message: any Message, expecting: any Message.Type, maxChunkSize: Int? = nil) -> (any Message)? {
        try? sendUntyped(message, expecting: expecting, maxChunkSize: maxChunkSize).get()
    }

    /// `write`, saying why there is no response.
    func send<R: PumpRequest>(_ request: R) -> Result<any Message, WriteFailure> {
        sendUntyped(request, expecting: R.Response.self, maxChunkSize: nil)
    }

    private func sendUntyped(
        _ message: any Message,
        expecting: any Message.Type,
        maxChunkSize: Int?
    ) -> Result<any Message, WriteFailure> {
        guard expecting.props.type == .Response else {
            logger.error("Cannot write \(type(of: message)): \(expecting) is not a response type")
            return .failure(.notSent)
        }

        // Pump I/O is already serialized by TandemBluetoothManager.commandQueue, so this lock
        // should never actually contend. It is kept purely as defense-in-depth, and the acquire
        // is bounded so that even an unexpected off-pipeline caller can never deadlock here (the
        // unbounded wait that used to live here was a primary cause of the connection hang).
        // On the success path the matching signal() is registered immediately via defer; on the
        // timeout path we never acquired the lock, so we must not signal.
        guard writeSemaphore.wait(wallTimeout: Self.writeLockTimeout) == .success else {
            logger.error("Timed out acquiring write lock; pump I/O unexpectedly contended")
            return .failure(.notSent)
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
            return .failure(.notSent)
        }

        let writeQ = TandemDispatchGroup()
        writeQ.enter()
        let pending = PendingWrite(
            group: writeQ,
            requestOpCode: requestProps.opCode,
            opCode: expecting.props.opCode,
            characteristic: characteristic.uuid,
            txId: currentTxId
        )
        guard begin({ _writeQueue = pending }) else {
            logger.error("Link is gone; not writing \(message.description)")
            return .failure(.notSent)
        }

        defer {
            writeQueue = nil
        }

        var authKey = Data()
        if requestProps.signed {
            authKey = pumpManager.state.pumpState.getAuthKey()
        }

        logger.info("Writing message: \(message.description)")
        var packetsWritten = 0
        for item in Packetize.parse(
            message: message,
            authenticationKey: authKey,
            txId: currentTxId,
            timeSinceReset: pumpManager.state.pumpState.timeSinceReset,
            maxChunkSize: maxChunkSize
        ) {
            let acknowledged = TandemDispatchGroup()
            acknowledged.enter()
            // The next connect reuses this CBPeripheral, so the rest of a request must not follow
            // a lost link onto the new one.
            guard begin({ _commandLock = acknowledged }) else {
                logger.error("Link is gone after \(packetsWritten) packets of \(message.description)")
                return .failure(packetsWritten == 0 ? .notSent : .linkLost(linkLoss ?? .other))
            }

            peripheral.writeValue(item.build(), for: characteristic, type: .withResponse)
            packetsWritten += 1
            acknowledged.wait(timeout: .seconds(2))
        }

        currentTxId = currentTxId &+ 1
        // Released by PendingWrite.append once the last packet has been reassembled.
        let wallStart = Date()
        let uptimeStart = DispatchTime.now().uptimeNanoseconds
        let outcome = writeQ.waitForOutcome(timeout: Self.responseTimeout)
        let wallElapsed = Date().timeIntervalSince(wallStart)
        let uptimeElapsed = Double(DispatchTime.now().uptimeNanoseconds &- uptimeStart) / 1e9
        let waited = String(format: "waited %.1fs wall, %.1fs uptime", wallElapsed, uptimeElapsed)
        guard case .completed = outcome else {
            if outcome == .cancelled {
                let loss = linkLoss ?? .other
                logger.error("Write cancelled before a response arrived; link lost (\(loss))")
                return .failure(.linkLost(loss))
            }
            logger.error("Timeout hit, no response from pump... (\(waited))")
            queueLock.lock()
            _unsolicitedLog.recordUnanswered(
                request: String(describing: type(of: message)),
                txId: pending.txId,
                responseOpCode: pending.opCode,
                characteristic: pending.characteristic,
                at: Date()
            )
            queueLock.unlock()
            return .failure(.unanswered)
        }

        if let refusal = pending.refusal {
            // No answer, as for a timeout: callers treat both as a failed command, and a refused
            // insulin-affecting request is reported no less cautiously than a lost one.
            logger.error("Pump refused \(message.description): \(refusal.description)")
            return .failure(.unanswered)
        }

        let message = pending.message
        logger.info("Received message: \(message?.description ?? "nil") (\(waited))")
        return message.map { .success($0) } ?? .failure(.unanswered)
    }

    /// Records why the link went away, then cancels the waits in flight, whose BLE callbacks can no
    /// longer arrive. Every operation begun afterwards is refused.
    func linkWentDown(_ loss: LinkLoss) {
        queueLock.lock()
        if _linkLoss == nil {
            _linkLoss = loss
        }
        let inFlight = (command: _commandLock, write: _writeQueue, read: _readQueue)
        queueLock.unlock()

        logger.info("Link lost (\(loss)); cancelling pending operations")
        inFlight.command?.cancel()
        inFlight.write?.group.cancel()
        inFlight.read?.0.cancel()
        // A partially assembled message can never complete once the connection drops.
        historyLogStream.reset()
        controlStream.reset()
        unsolicited = [:]
    }

    func startNotify(service serviceUUID: CBUUID, characteristic characteristicUUID: CBUUID) {
        guard let characteristic = getCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            return
        }

        let acknowledged = TandemDispatchGroup()
        acknowledged.enter()
        guard begin({ _commandLock = acknowledged }) else {
            return
        }

        peripheral.setNotifyValue(true, for: characteristic)
        acknowledged.wait(timeout: .seconds(2))
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

        // The stream and event characteristics carry nothing any write waits for, and pieces of
        // their messages can match a pending write's opcode at byte 2.
        switch characteristic.uuid {
        case CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS:
            handleHistoryLogStreamPacket(data)
        case CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS:
            handleControlStreamPacket(data)
        case CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS:
            handleQualifyingEvents(data, on: characteristic)
        default:
            if let pending = writeQueue, let taken = pending.take(data, on: characteristic.uuid) {
                report(taken, for: pending, on: characteristic.uuid)
            } else {
                handleUnsolicited(data, on: characteristic.uuid)
            }
        }
    }

    private func report(_ taken: PendingWrite.Taken, for pending: PendingWrite, on characteristic: CBUUID) {
        switch taken {
        case .needsMore:
            logger.info("Waiting for more data...")
        case .answered:
            break
        case let .refused(refusal):
            logger.error("Received error message: \(refusal.description)")
        case let .discarded(reason):
            let channel = MessageCategory(characteristic: characteristic).rawValue
            logger.warning("Discarded a message under txId \(pending.txId) on \(channel): \(reason); the write still waits")
        }
    }

    private func handleQualifyingEvents(_ data: Data, on characteristic: CBCharacteristic) {
        let events = QualifyingEvent.fromRawBytes(data)
        guard !events.isEmpty else {
            logger.info("Received empty qualifying events")
            return
        }

        let acknowledge = { self.peripheral.writeValue(Data([0, 0, 0, 0]), for: characteristic, type: .withResponse) }
        if deferUntilSessionEstablished(events) {
            logger.info("Deferring qualifying events until setup finishes: \(events)")
            acknowledge()
            return
        }
        pumpManager.handleQualifyingEvents(events: events, completion: acknowledge)
    }

    /// A stream's messages follow one another, so a piece that starts a message while another is
    /// under way means that one lost a piece, and it is dropped for the new one.
    private static func takeStartingOver(_ data: Data, into assembler: inout PacketAssembler) -> (PacketAssembler.Step, abandoned: Bool) {
        let abandoned = !assembler.isEmpty && !assembler.continues(with: data) && PacketAssembler.start(of: data) != nil
        if abandoned {
            assembler.reset()
        }
        return (assembler.take(data), abandoned)
    }

    private func takeStreamPacket(_ data: Data, into assembler: inout PacketAssembler, stream: String) -> AssembledMessage? {
        let (step, abandoned) = Self.takeStartingOver(data, into: &assembler)
        if abandoned {
            logger.warning("A \(stream) stream message lost a piece and was dropped")
        }
        switch step {
        case let .complete(message):
            return message
        case .needsMore:
            return nil
        case .notPart:
            logger.warning("Not part of a \(stream) stream message: \(data.hexadecimalString)")
            return nil
        case let .corrupt(reason):
            logger.warning("Dropped a \(stream) stream message: \(reason)")
            return nil
        }
    }

    private func handleHistoryLogStreamPacket(_ data: Data) {
        guard let message = takeStreamPacket(data, into: &historyLogStream, stream: "history log") else { return }
        guard let response = BTResponseParser.decode(message, characteristic: CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS)
            as? HistoryLogStreamResponse
        else {
            logger.warning("Unparseable history log stream message: opCode \(message.opCode), cargo \(message.cargo.hexadecimalString)")
            return
        }
        logger.info("Received stream message: \(response.description)")
        pumpManager.historyLogStream.send(response)
    }

    private func handleControlStreamPacket(_ data: Data) {
        guard let message = takeStreamPacket(data, into: &controlStream, stream: "control") else { return }
        guard let type = ControlStreamMessages.responseType(opCode: message.opCode, payloadLength: message.payloadLength),
              message.cargo.count >= Int(type.props.size)
        else {
            logger.warning("Unknown control stream message: opCode \(message.opCode), cargo \(message.cargo.hexadecimalString)")
            return
        }

        let response = type.init(cargo: message.cargo)
        logger.info("Received stream message: \(response.description)")
        switch response {
        case let response as FillTubingStateStreamResponse:
            pumpManager.fillTubingStateStream.send(response)
        case let response as FillCannulaStateStreamResponse:
            pumpManager.fillCannulaStateStream.send(response)
        case let response as EnterChangeCartridgeModeStateStreamResponse:
            pumpManager.changeCartridgeStateStream.send(response)
        case let response as DetectingCartridgeStateStreamResponse:
            pumpManager.detectingCartridgeStateStream.send(response)
        case let response as PumpingStateStreamResponse:
            pumpManager.pumpingStateStream.send(response)
        case let response as ExitFillTubingModeStateStreamResponse:
            pumpManager.exitFillTubingModeStateStream.send(response)
        default:
            break
        }
    }

    /// Responses no write was waiting for, reassembled per characteristic so that each is logged
    /// once, by name.
    private func handleUnsolicited(_ data: Data, on characteristic: CBUUID) {
        guard Self.requestCharacteristics.contains(characteristic) else {
            logger.warning("Not handler for message - data: \(data.hexadecimalString) characteristic: \(characteristic)")
            return
        }

        let channel = MessageCategory(characteristic: characteristic).rawValue
        var assembler = unsolicited[characteristic] ?? PacketAssembler()
        let (step, _) = Self.takeStartingOver(data, into: &assembler)
        unsolicited[characteristic] = assembler
        switch step {
        case let .complete(message):
            logUnsolicited(message, on: characteristic)
        case .needsMore:
            break
        case .notPart:
            logger.debug("Unsolicited fragment on \(channel): \(data.hexadecimalString)")
        case let .corrupt(reason):
            logger.debug("Unsolicited message on \(channel) dropped: \(reason)")
        }
    }

    private func logUnsolicited(_ message: AssembledMessage, on characteristic: CBUUID) {
        let name: String
        if message.opCode == ErrorResponse.props.opCode, message.payloadLength >= 2 {
            name = ErrorResponse(cargo: message.cargo).description
        } else {
            name = MessageRegistry.findResponse(opCode: message.opCode, characteristic: characteristic)
                .map { String(describing: $0) } ?? "opCode \(message.opCode)"
        }
        let what = "\(name) (txId \(message.txId)) on \(MessageCategory(characteristic: characteristic).rawValue)"

        queueLock.lock()
        let kind = _unsolicitedLog.classify(message, on: characteristic, at: Date())
        queueLock.unlock()
        switch kind {
        case let .lateAnswer(request, seconds):
            logger.info("Late answer to \(request), \(String(format: "%.1f", seconds)) s after it timed out: \(what)")
        case .startsBurst:
            logger.info("Unsolicited \(what): no write was waiting for it, so another app on the phone is likely talking to the pump; more within \(Int(UnsolicitedNotificationLog.quietGap)) s are logged at debug")
        case let .inBurst(count):
            logger.debug("Unsolicited \(what), #\(count) of this burst")
        }
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
    /// during connection setup, while awaitConnect is parked in its wait on the command queue —
    /// no other command can be in flight. Keep it that way: setup must stay confined to the window
    /// before awaitConnect returns.
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

            if let loss = linkLoss {
                logger.error("Link lost (\(loss)) before authenticating")
                failSetup(PumpCommError.noResponse)
                return
            }

            if !authBuilder.done() {
                logger.info("Doing jpake pairing")
                JpakeAuthBuilder.clearInstance()

                let pincode = pumpManager.state.pumpState.pincode ?? self.fallbackPairingCode
                let isFirstPairing = pumpManager.state.pumpState.derivedSecret == nil
                if let derivedSecret = pumpManager.state.pumpState.derivedSecret {
                    authBuilder = JpakeAuthBuilder.initializeWithDerivedSecret(pairingCode: pincode, derivedSecret: derivedSecret)
                } else {
                    authBuilder = JpakeAuthBuilder.initializeWithPairingCode(pincode)
                }

                // Only a paired pump's reconnects are limited; a first pairing is the user's own attempt.
                func failHandshake(_ error: PumpCommError, counted: Bool = true) {
                    if !isFirstPairing {
                        if counted {
                            bluetoothManager.recordJpakeFailure()
                        } else {
                            logger.info("Not counted as the pump ending the handshake")
                        }
                    }
                    failSetup(error)
                }

                while let request = authBuilder.nextRequest() {
                    let response: any Message
                    switch send(request) {
                    case let .success(answer):
                        response = answer
                    case let .failure(failure):
                        logger.error("No answer to \(type(of: request)) during JPAKE: \(failure)")
                        // The pump checks the code only at key confirmation, and a Mobi answers a wrong
                        // one by dropping the link.
                        let rejected = isFirstPairing && request is Jpake4KeyConfirmationRequest && failure != .notSent
                        failHandshake(
                            rejected ? PumpCommError.pairingCodeRejected : PumpCommError.noResponse,
                            counted: failure.countsAsJpakeFailure
                        )
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

                    // Must complete the connect attempt, otherwise awaitConnect blocks for its
                    // full timeout and stalls every queued command behind it.
                    failHandshake(isFirstPairing && authBuilder.rejectedAtKeyConfirmation()
                        ? PumpCommError.pairingCodeRejected
                        : PumpCommError.noResponse)
                    return
                }

                bluetoothManager.recordJpakeSuccess()
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
