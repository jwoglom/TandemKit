import CoreBluetooth

/// Heap box carrying a single connect attempt's result from its (cross-thread) completion handler
/// back to the waiting awaitConnect. The DispatchSemaphore in TandemDispatchGroup provides the
/// happens-before ordering between the write here and the read after `wait`.
private final class ConnectResultBox {
    var error: Error?
}

class TandemBluetoothManager: NSObject, PumpBluetoothConnection {
    private let logger = TandemLogger(category: "TandemBluetoothManager")
    private let managerQueue = DispatchQueue(label: "com.jwoglom.TandemKit.bluetoothManagerQueue", qos: .unspecified)

    // Weak: the pump manager owns this bluetooth manager, so a strong back-reference here forms a
    // retain cycle that keeps a deleted TandemPumpManager (and its auto-reconnecting BLE session)
    // alive forever. StubPumpBluetooth already models this as weak.
    public weak var pumpManager: TandemPumpManager? {
        didSet {
            guard oldValue == nil, pumpManager != nil else { return }
            managerQueue.async { [weak self] in
                guard let self, self.manager?.state == .poweredOn else { return }
                self.autoReconnect()
            }
        }
    }

    private(set) var manager: CBCentralManager?
    private var peripheral: CBPeripheral?

    // Read from the command queue and from setup tasks on global queues, written on managerQueue,
    // so the reference access goes through connectStateLock. The lock only covers get/set of the
    // reference; blocking pump I/O on the referenced manager happens outside it.
    private var _peripheralManager: TandemPeripheralManager?
    private var peripheralManager: TandemPeripheralManager? {
        get { connectStateLock.lock()
            defer { connectStateLock.unlock() }
            return _peripheralManager }
        set { connectStateLock.lock()
            _peripheralManager = newValue
            connectStateLock.unlock() }
    }

    /// True while `candidate` is still the live peripheral manager. An orphaned setup task keeps
    /// running after a drop and must not act on a connection that is no longer its own.
    func isCurrentPeripheralManager(_ candidate: TandemPeripheralManager) -> Bool {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        return _peripheralManager === candidate
    }

    private var scanCompletion: ((_ result: TandemPumpScan) -> Void)?
    // Set on commandQueue or managerQueue, taken on managerQueue; guarded by connectStateLock.
    private var _connectCompletion: ((Error?) -> Void)?

    // All pump interaction (connect + every command job) is serialized onto this single
    // serial queue. Serializing here is what guarantees only one connect/command runs at a
    // time, which removes the need for a separate connection semaphore and eliminates the
    // race between loop commands and qualifying-event handlers contending on the write path.
    private let commandQueue = DispatchQueue(label: "com.jwoglom.TandemKit.commandQueue")
    // Upper bound on a single connect attempt. The wait that enforces this is intrinsic to a
    // DispatchSemaphore (see awaitConnect), so — unlike the previous asyncAfter-based
    // safety net that sat on the very queue it was meant to rescue — it can never be starved.
    private var connectTimeout: DispatchTimeInterval {
        #if TANDEMKIT_VIRTUAL_PUMP
        if let override = VirtualPump.connectTimeout { return override }
        #endif
        return .seconds(30)
    }
    // Pairing runs JPAKE on top of the connect, and had no bound at all before it was a command job.
    var pairingTimeout: DispatchTimeInterval = .seconds(120)
    // The in-flight connect attempt's wait group, so a disconnect / Bluetooth-off can cancel it and
    // release awaitConnect immediately rather than letting it block out its full timeout.
    // Guarded by connectStateLock because it is set on commandQueue and cancelled on managerQueue.
    private let connectStateLock = NSLock()
    private var inFlightConnectGroup: TandemDispatchGroup?
    // Set on delete, never cleared: refuses every connect, even a command job queued before the
    // delete, so a removed pump cannot take back its link. Locked because deactivate() is off-queue.
    private var isDeactivated = false
    // Responses the pump has actually returned. Bumped on commandQueue and read from the command
    // jobs there, but guarded by connectStateLock so an off-queue reader cannot race the increment.
    private var _responseCount = 0
    // Consecutive connect attempts that ended without a usable session. Only touched from
    // awaitConnect, i.e. only on commandQueue, so it needs no lock.
    private var consecutiveConnectFailures = 0
    // Failures tolerated on the fast paths (a cached CBPeripheral, or one CoreBluetooth still
    // lists as connected) before they are discarded and the pump is rediscovered by scanning.
    // Two, so a single dropout that resolves itself does not pay for a rescan.
    private let staleFastPathThreshold = 2
    // CoreBluetooth says nothing when a pump that refused a connect comes back into range, and the
    // host's sync is throttled for minutes after the last one, so a failed connect on a paired pump
    // is retried on this schedule until a session lands (jwoglom/tandemkit-stress#4).
    var reconnectRetryDelays: [TimeInterval] = [5, 10, 20, 40, 60]
    // Guarded by connectStateLock: scheduled from command jobs, cancelled from managerQueue
    // (Bluetooth off) and from deactivate().
    private var reconnectRetry: DispatchWorkItem?
    private var reconnectRetryCount = 0
    // Handshakes in a row the pump ended or left unanswered before the driver stops reconnecting on
    // its own: one lost to a dropout is ordinary. Written from setup tasks on global queues and read
    // by the UI, so guarded by connectStateLock.
    static let jpakeFailureLimit = 3
    private var consecutiveJpakeFailures = 0

    var isJpakeFailureLimitReached: Bool {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        return consecutiveJpakeFailures >= Self.jpakeFailureLimit
    }

    var isActive: Bool {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        return !isDeactivated
    }

    private func setInFlightConnectGroup(_ group: TandemDispatchGroup?) {
        connectStateLock.lock()
        inFlightConnectGroup = group
        connectStateLock.unlock()
    }

    /// False once deactivated: `deactivate` ends the completion it finds, so one armed after it
    /// looked would wait out its timeout. Both go through the lock, so a connect is one or the other.
    private func armConnectCompletion(_ completion: @escaping (Error?) -> Void) -> Bool {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        guard !isDeactivated else {
            return false
        }
        _connectCompletion = completion
        return true
    }

    private func takeConnectCompletion() -> ((Error?) -> Void)? {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        let completion = _connectCompletion
        _connectCompletion = nil
        return completion
    }

    private func cancelInFlightConnect() {
        connectStateLock.lock()
        let group = inFlightConnectGroup
        connectStateLock.unlock()
        group?.cancel()
    }

    var bluetoothState: CBManagerState {
        manager?.state ?? .unknown
    }

    var responseCount: Int {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        return _responseCount
    }

    /// A peripheral CoreBluetooth reports connected, with a peripheral manager from setup.
    private var hasLiveSession: Bool {
        guard let peripheral else {
            return false
        }
        return peripheral.state == .connected && peripheralManager != nil
    }

    /// Drops the now-invalid peripheral manager and publishes the change, so nothing above goes on
    /// claiming a link that no longer exists. Called from each of the three ways a session ends:
    /// the peripheral disconnecting, the radio leaving `poweredOn`, and a connect attempt failing.
    private func markLinkDown() {
        peripheralManager = nil

        guard let pumpManager else {
            return
        }
        pumpManager.state.isConnected = false
        pumpManager.notifyDelegateStateUpdated()
    }

    override init() {
        super.init()

        managerQueue.sync {
            self.manager = CBCentralManager(
                delegate: self,
                queue: managerQueue
            )
        }
    }

    deinit {
        self.manager = nil
    }

    func startScan(_ completion: @escaping (_ result: TandemPumpScan) -> Void) -> Bool {
        guard let manager, manager.state == .poweredOn else {
            return false
        }

        stopScan()

        scanCompletion = completion
        manager.scanForPeripherals(
            withServices: [ServiceUUID.PUMP_SERVICE],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        logger.info("Started scanning")
        return true
    }

    func stopScan() {
        guard let manager else {
            logger.error("No CBCentralManager")
            return
        }

        if manager.isScanning {
            manager.stopScan()
            scanCompletion = nil
        }
    }

    func connectedPumpNames() -> [String] {
        guard let manager else { return [] }
        return manager.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
            .map { $0.name ?? "Tandem Mobi" }
    }

    /// Pairing's connect, as a command job: a job queued meanwhile finds the session up instead of
    /// connecting again, which took over this connect's completion and left pairing waiting forever.
    func connect(_ peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        commandQueue.async {
            guard self.isActive else {
                self.logger.info("Pump deactivated; refusing to connect")
                completion(PumpCommError.pumpNotConnected)
                return
            }
            guard let manager = self.manager else {
                self.logger.error("No CBCentralManager")
                completion(PumpCommError.pumpNotConnected)
                return
            }
            // A job queued first may have connected a pump that already holds a key; a connect to a
            // peripheral already connected is never answered, so pairing would wait out its timeout.
            if self.hasLiveSession, self.peripheral?.identifier == peripheral.identifier {
                self.logger.info("Pump already connected; pairing uses that session")
                self.stopScan()
                completion(nil)
                return
            }
            // A dropped link leaves the attempt to the setup, which knows the round it lost: a Mobi
            // refuses a wrong code by dropping the link at key confirmation.
            completion(self.awaitConnect(on: manager, timeout: self.pairingTimeout, endsOnLinkLoss: false) { onConnect in
                self.startConnect(peripheral, on: manager, completion: onConnect)
                return nil
            })
        }
    }

    /// Only from an `awaitConnect` start, so `commandQueue` is waiting on this connect alone.
    private func startConnect(_ peripheral: CBPeripheral, on manager: CBCentralManager, completion: @escaping (Error?) -> Void) {
        stopScan()

        logger.info("Connecting to \(peripheral)")

        self.peripheral = peripheral
        guard armConnectCompletion(completion) else {
            logger.info("Pump deactivated; refusing to connect")
            completion(PumpCommError.pumpNotConnected)
            return
        }

        manager.connect(peripheral)
    }

    /// Blocks until the pump responds, so it must run as part of a serialized command job — i.e.
    /// inside an `ensureConnected` block. Off-queue writes race the command pipeline and were a
    /// root cause of the wedged-connection failures.
    func write<R: PumpRequest>(_ request: R, maxChunkSize: Int? = nil) -> R.Response? {
        dispatchPrecondition(condition: .onQueue(commandQueue))

        guard let peripheralManager else {
            logger.error("No peripheralManager -> Not connected...")
            return nil
        }

        return countingResponse(peripheralManager.write(request, maxChunkSize: maxChunkSize))
    }

    func writeUntyped(_ message: any Message, expecting: any Message.Type, maxChunkSize: Int? = nil) -> (any Message)? {
        dispatchPrecondition(condition: .onQueue(commandQueue))

        guard let peripheralManager else {
            logger.error("No peripheralManager -> Not connected...")
            return nil
        }

        return countingResponse(peripheralManager.writeUntyped(message, expecting: expecting, maxChunkSize: maxChunkSize))
    }

    /// Counts `response` towards `responseCount` when the pump returned one, and passes it through.
    private func countingResponse<T>(_ response: T?) -> T? {
        guard response != nil else {
            return nil
        }

        connectStateLock.lock()
        _responseCount += 1
        connectStateLock.unlock()
        return response
    }

    /// Runs `completion` as a serialized command job: the pump is connected if necessary, then
    /// `completion` runs on `commandQueue` so its (blocking) writes are serialized against every
    /// other command and against connection setup. `completion` always runs exactly once, with a
    /// non-nil error if the connection could not be established within `connectTimeout`.
    func ensureConnected(completion: @escaping (Error?) -> Void) {
        runConnectJob(automatic: false, completion: completion)
    }

    func pumpManagerWasAdopted() {
        managerQueue.async { [weak self] in
            guard let self, self.manager?.state == .poweredOn else { return }
            self.autoReconnect()
        }
    }

    /// A connect the driver starts on its own, which `isJpakeFailureLimitReached` stops, as does no
    /// host having adopted the manager (`canNotifyDelegate`). A host command still tries: only an
    /// attempt can tell the pump has stopped refusing, and a host cycle is minutes apart, not the
    /// seconds a disconnect-triggered retry is.
    func reconnectAutomatically(completion: @escaping (Error?) -> Void) {
        runConnectJob(automatic: true, completion: completion)
    }

    private func runConnectJob(automatic: Bool, completion: @escaping (Error?) -> Void) {
        commandQueue.async {
            // A setup flow's manager connects as a command when it needs to; one left behind kept
            // the pump's one link against every attempt after it (#603).
            if automatic, self.pumpManager?.canNotifyDelegate != true {
                self.logger.info("No host has adopted this pump manager; not reconnecting automatically")
                completion(PumpCommError.pumpNotConnected)
                return
            }
            if automatic, self.isJpakeFailureLimitReached {
                self.logger.info("The pump keeps ending the handshake; not reconnecting automatically")
                completion(PumpCommError.pumpNotConnected)
                return
            }
            let hadSession = self.hasLiveSession
            let error = self.connectIfNeeded()
            // Covers every way connectIfNeeded can fail, including the ones CoreBluetooth never
            // reports as a disconnect. A session that landed since the attempt gave up is live.
            if error != nil, !self.hasLiveSession {
                self.markLinkDown()
                self.scheduleReconnectRetry()
            }
            if error == nil, !hadSession {
                self.pumpManager?.didReconnect()
            }
            completion(error)
        }
    }

    /// Arms the next background connect attempt, unless one is already pending. Only for a pump
    /// that has been paired, and a manager a host has adopted: an unpaired one has nothing to
    /// reconnect to, and an unadopted one's retry would be refused.
    private func scheduleReconnectRetry() {
        guard isActive, !isJpakeFailureLimitReached, manager?.state == .poweredOn, pumpManager?.isOnboarded == true,
              pumpManager?.canNotifyDelegate == true
        else {
            return
        }

        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        if let pending = reconnectRetry, !pending.isCancelled {
            return
        }
        let delays = reconnectRetryDelays
        let delay = delays[min(reconnectRetryCount, delays.count - 1)]
        reconnectRetryCount += 1
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.connectStateLock.lock()
            self.reconnectRetry = nil
            self.connectStateLock.unlock()
            self.logger.info("Retrying the reconnect")
            self.reconnectAutomatically { error in
                if error == nil {
                    self.logger.info("Reconnect retry completed!")
                }
            }
        }
        reconnectRetry = item
        logger.info("Retrying the reconnect in \(delay) s")
        managerQueue.asyncAfter(wallInterval: .milliseconds(Int((delay * 1000).rounded())), execute: item)
    }

    private func cancelReconnectRetry() {
        connectStateLock.lock()
        reconnectRetry?.cancel()
        reconnectRetry = nil
        reconnectRetryCount = 0
        connectStateLock.unlock()
    }

    /// Called from the setup task when the pump may have ended the handshake or never answered it.
    /// Reported with a second host paired to the same pump: it accepts the link, then drops it.
    func recordJpakeFailure() {
        connectStateLock.lock()
        consecutiveJpakeFailures += 1
        let failures = consecutiveJpakeFailures
        connectStateLock.unlock()

        logger.warning("JPAKE handshake failed (\(failures) in a row)")
        guard failures == Self.jpakeFailureLimit else {
            return
        }

        logger.error("The pump ended the handshake \(failures) times in a row; no longer reconnecting automatically")
        cancelReconnectRetry()
        pumpManager?.notifyDelegateStateUpdated()
    }

    func recordJpakeSuccess() {
        resetJpakeFailures()
    }

    private func resetJpakeFailures() {
        connectStateLock.lock()
        let wasAtLimit = consecutiveJpakeFailures >= Self.jpakeFailureLimit
        consecutiveJpakeFailures = 0
        connectStateLock.unlock()

        if wasAtLimit {
            logger.info("Handshake failures cleared; reconnecting automatically again")
            pumpManager?.notifyDelegateStateUpdated()
        }
    }

    /// Establishes a connection to the pump if one is not already up. MUST be called on
    /// `commandQueue`. Blocks (bounded by `connectTimeout`) until the connection is ready or the
    /// attempt fails/times out, returning nil on success and an error otherwise.
    ///
    /// The bounded wait is a wall-clock `DispatchSemaphore.wait` (via TandemDispatchGroup): the
    /// timeout is intrinsic to the wait and needs no separate timer, so it cannot be starved by
    /// this queue being blocked — which is exactly the failure mode of the previous design.
    private func connectIfNeeded() -> Error? {
        guard isActive else {
            logger.info("Pump deactivated; refusing to connect")
            return PumpCommError.pumpNotConnected
        }

        if hasLiveSession {
            consecutiveConnectFailures = 0
            cancelReconnectRetry()
            return nil
        }

        // Only pairPump starts a first pairing; a reconnect would replay the last code entered at a
        // pump that just refused it.
        guard pumpManager?.isOnboarded == true else {
            logger.info("Pump is not paired; not connecting")
            return PumpCommError.pumpNotConnected
        }

        guard let manager else {
            return PumpCommError.pumpNotConnected
        }
        guard manager.state == .poweredOn else {
            logger.error("Bluetooth not powered on (state \(manager.state.rawValue)); cannot connect")
            return PumpCommError.pumpNotConnected
        }

        // A run of failures means the fast paths below are no longer working, and replaying one
        // forever gets nowhere. Discard the cached references so the pump is rediscovered.
        var rediscovering = false
        if consecutiveConnectFailures >= staleFastPathThreshold {
            logger
                .info(
                    "\(consecutiveConnectFailures) consecutive connect failures; discarding cached peripheral and rediscovering"
                )
            discardCachedPeripheral(on: manager)
            rediscovering = true
        }

        return awaitConnect(on: manager, timeout: connectTimeout) { onConnect in
            if let peripheral {
                // Reuse the peripheral reference from a previous connection.
                startConnect(peripheral, on: manager, completion: onConnect)
            } else if !rediscovering,
                      let peripheral = manager.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]).first
            {
                // Phone is already connected to the pump, but the app is not.
                startConnect(peripheral, on: manager, completion: onConnect)
            } else if let identifier = pumpManager?.state.pumpState.peripheralUuid {
                // When rediscovering, this is the only path taken: cancelPeripheralConnection is
                // asynchronous, so the peripheral we just discarded can still be in the OS's
                // connected list for a moment, and reusing it from there would defeat the rescan.
                let scanStarted = startScan { result in
                    guard result.bleIdentifier == identifier else {
                        return
                    }
                    self.logger.debug("Found pump, reconnecting! \(result.peripheral)")
                    self.startConnect(result.peripheral, on: manager, completion: onConnect)
                }
                if !scanStarted {
                    return PumpCommError.pumpNotConnected
                }
            } else {
                logger.error("No identifier available to scan for...")
                return PumpCommError.pumpNotConnected
            }
            return nil
        }
    }

    /// Starts a connect through `start`, which returns an error when it could not, and waits for
    /// it until `timeout`, or with `endsOnLinkLoss` until the link or Bluetooth goes away. MUST be
    /// called on `commandQueue`.
    private func awaitConnect(
        on manager: CBCentralManager,
        timeout: DispatchTimeInterval,
        endsOnLinkLoss: Bool = true,
        _ start: (_ onConnect: @escaping (Error?) -> Void) -> Error?
    ) -> Error? {
        let group = TandemDispatchGroup()
        group.enter()
        if endsOnLinkLoss {
            setInFlightConnectGroup(group)
        }
        defer { setInFlightConnectGroup(nil) }

        // Per-attempt result holder so a late/stale connect callback from a previous attempt can
        // never clobber the result of the current one. Ordered after the wait by the semaphore.
        let resultBox = ConnectResultBox()
        let onConnect: (Error?) -> Void = { error in
            resultBox.error = error
            group.leave(Data())
        }

        if let error = start(onConnect) {
            return error
        }

        // Cancelled by cancelInFlightConnect() on disconnect/Bluetooth-off, or times out on its own.
        switch group.waitForOutcome(timeout: timeout) {
        case .timedOut:
            logger.error("Connect attempt did not complete within \(timeout)")
            abandonConnectAttempt(on: manager)
            consecutiveConnectFailures += 1
            return PumpCommError.pumpNotConnected

        case .cancelled:
            // Released early because the link went away, not out of time. Distinct from .timedOut.
            logger.error("Connect attempt cancelled before completing; link or Bluetooth went away")
            abandonConnectAttempt(on: manager)
            consecutiveConnectFailures += 1
            return PumpCommError.pumpNotConnected

        case .completed:
            if let error = resultBox.error {
                consecutiveConnectFailures += 1
                return error
            }
            consecutiveConnectFailures = 0
            cancelReconnectRetry()
            return nil
        }
    }

    /// Releases the CoreBluetooth resources of a connect attempt we have stopped waiting for.
    /// `CBCentralManager.connect(_:)` has no timeout and stays pending until cancelled, so
    /// abandoned attempts otherwise pile up in the OS. MUST be called on `commandQueue`.
    private func abandonConnectAttempt(on manager: CBCentralManager) {
        stopScan()

        // A session may have landed between the wait giving up and this call; that one is live and
        // is not ours to tear down.
        guard let peripheral, !hasLiveSession else {
            return
        }
        manager.cancelPeripheralConnection(peripheral)
    }

    /// Drops the cached peripheral reference, and cancels any connection CoreBluetooth still holds
    /// to the pump, so the next attempt has to rediscover it by scanning. MUST be called on
    /// `commandQueue`, and only when there is no live session (see the caller's guard).
    private func discardCachedPeripheral(on manager: CBCentralManager) {
        if let peripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
        // Also drop anything the OS still lists as a connected pump: that list is the second fast
        // path, and a stale entry in it is just as able to wedge every future attempt.
        for stale in manager.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]) {
            manager.cancelPeripheralConnection(stale)
        }

        peripheral = nil
        peripheralManager = nil
        consecutiveConnectFailures = 0
    }

    func disconnect() {
        // Signed: on a link that never authenticated the pump cannot answer it, and waiting for
        // that cost every failed setup the full response timeout.
        if let peripheralManager, peripheralManager.isSessionEstablished {
            _ = peripheralManager.write(DisconnectPumpRequest())
        }

        if let manager {
            if manager.isScanning {
                manager.stopScan()
            }

            if let peripheral {
                manager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    /// Tear down for good: stop the automatic reconnect paths, drop the pump peripheral, and release
    /// the back-reference. Called when the pump is deleted so the session cannot resurrect itself.
    func deactivate() {
        connectStateLock.lock()
        isDeactivated = true
        connectStateLock.unlock()

        cancelReconnectRetry()
        // Pairing's wait outlives a lost link on purpose, so a connect still pending is ended here.
        takeConnectCompletion()?(PumpCommError.pumpNotConnected)
        disconnect()
        pumpManager = nil
    }
}

extension TandemBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        applyBluetoothState(central.state)
    }

    /// Drives the delegate callback without a live `CBCentralManager`, whose `state` cannot be set on
    /// Apple platforms. On managerQueue like the callback, so it cannot race the real central's own
    /// state delivery: two `markLinkDown()`s at once reassign the pump state and crash.
    func handleBluetoothStateChange(_ state: CBManagerState) {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        managerQueue.sync { applyBluetoothState(state) }
    }

    private func applyBluetoothState(_ state: CBManagerState) {
        logger.info("\(String(describing: state.rawValue))")

        guard state == .poweredOn else {
            // Bluetooth went away (powered off / resetting / unauthorized). The
            // peripheral's CB operations are now invalid and their callbacks
            // won't fire, so cancel in-flight command waits to release any held
            // locks instead of waiting for the stack to come back.
            logger.info("Bluetooth not powered on; cancelling pending operations")
            cancelReconnectRetry()
            peripheralManager?.linkWentDown(.bluetooth)
            cancelInFlightConnect()
            // No didDisconnectPeripheral arrives for those, so this is the only notice.
            markLinkDown()
            return
        }

        // So the UI stops blaming Bluetooth before the reconnect has even been attempted.
        pumpManager?.notifyDelegateStateUpdated()

        // Turning Bluetooth back on is the one thing a person can do to ask for a fresh attempt.
        resetJpakeFailures()
        autoReconnect()
    }

    /// On managerQueue, once Bluetooth is on and again once the pump manager is attached: the central can report
    /// poweredOn before the manager holding the pump's identifier is attached to it.
    private func autoReconnect() {
        guard isActive else {
            logger.info("Pump deactivated; not auto-reconnecting")
            return
        }
        guard pumpManager != nil else {
            logger.info("No pump manager attached yet; connecting once it is")
            return
        }

        reconnectAutomatically { error in
            if let error {
                self.logger.error("Failed to auto-reconnect: \(error)")
            } else {
                self.logger.info("Auto-reconnected completed!")
            }
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        scanCompletion?(TandemPumpScan(
            bleIdentifier: peripheral.identifier.uuidString,
            name: peripheral.name ?? "",
            peripheral: peripheral,
            advertisementData: advertisementData
        ))
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to pump: \(peripheral.name ?? "<NO_NAME>")!")

        guard let pumpManager = pumpManager else {
            logger.warning("No pumpManager...")
            return
        }
        // Taken, not read: the peripheral manager now owns it (fired at the end of
        // performInitialSetup, or on a setup error), so a later disconnect auto-reconnects instead.
        guard let completion = takeConnectCompletion() else {
            logger.warning("No connectCompletion...")
            return
        }

        self.peripheral = peripheral
        peripheralManager = TandemPeripheralManager(self, peripheral, pumpManager, completion)

        peripheral.discoverServices(ServiceUUID.all)
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info(
            "Device disconnected, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
        )

        // Before anything unblocks commandQueue: the next job's connect is not this link's, and
        // failing it here dropped its didConnect and orphaned the link it opened.
        let pendingConnect = takeConnectCompletion()

        // Unblock any command thread parked on an in-flight BLE operation. The callbacks that
        // would normally release these waits (didWriteValueFor / didUpdateValueFor) will never
        // arrive now that the peripheral is gone, so without this a blocked write()/read() would
        // sit on the command queue until its bounded timeout. Cancelling lets it unwind promptly.
        // Also release any in-flight connect attempt (e.g. a disconnect mid-performInitialSetup),
        // which would otherwise block awaitConnect for its full timeout.
        // linkWentDown first: the connect job this releases clears peripheralManager, and a setup
        // task never told of the drop went on to write JPAKE on the next connection.
        peripheralManager?.linkWentDown(TandemPeripheralManager.LinkLoss(disconnectError: error))
        cancelInFlightConnect()
        markLinkDown()

        if let pendingConnect {
            pendingConnect(PumpCommError.pumpNotConnected)
        } else if isActive {
            logger.debug("Auto reconnect...")
            reconnectAutomatically { error in
                if let error = error {
                    self.logger.warning("Failed to auto-reconnect: \(error)")
                }
            }
        } else {
            logger.info("Pump deactivated; skipping auto-reconnect")
        }
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.info(
            "Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
        )

        // Complete the in-flight connect attempt promptly so awaitConnect returns an error
        // immediately rather than waiting out its timeout.
        if let connectCompletion = takeConnectCompletion() {
            connectCompletion(
                PumpCommError
                    .errorResponse(context: "Failed to connect: \(error?.localizedDescription ?? "unknown")")
            )
        }
    }
}
