import CoreBluetooth

/// Heap box carrying a single connect attempt's result from its (cross-thread) completion handler
/// back to the waiting connectIfNeeded. The DispatchSemaphore in TandemDispatchGroup provides the
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
    public weak var pumpManager: TandemPumpManager?

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
    private var connectCompletion: ((Error?) -> Void)?

    // All pump interaction (connect + every command job) is serialized onto this single
    // serial queue. Serializing here is what guarantees only one connect/command runs at a
    // time, which removes the need for a separate connection semaphore and eliminates the
    // race between loop commands and qualifying-event handlers contending on the write path.
    private let commandQueue = DispatchQueue(label: "com.jwoglom.TandemKit.commandQueue")
    // Upper bound on a single connect attempt. The wait that enforces this is intrinsic to a
    // DispatchSemaphore (see connectIfNeeded), so — unlike the previous asyncAfter-based
    // safety net that sat on the very queue it was meant to rescue — it can never be starved.
    private let connectTimeout: DispatchTimeInterval = .seconds(30)
    // The in-flight connect attempt's wait group, so a disconnect / Bluetooth-off can cancel it and
    // release connectIfNeeded immediately rather than letting it block out the full connectTimeout.
    // Guarded by connectStateLock because it is set on commandQueue and cancelled on managerQueue.
    private let connectStateLock = NSLock()
    private var inFlightConnectGroup: TandemDispatchGroup?
    // Set once the pump is deactivated/deleted. Suppresses the automatic reconnect paths so a
    // removed pump does not silently re-establish its session and re-persist its state. Guarded by
    // connectStateLock because it is set off-queue (from deactivate()) and read on managerQueue.
    private var isDeactivated = false
    // Responses the pump has actually returned. Bumped on commandQueue and read from the command
    // jobs there, but guarded by connectStateLock so an off-queue reader cannot race the increment.
    private var _responseCount = 0
    // Consecutive connect attempts that ended without a usable session. Only touched from
    // connectIfNeeded, i.e. only on commandQueue, so it needs no lock.
    private var consecutiveConnectFailures = 0
    // Failures tolerated on the fast paths (a cached CBPeripheral, or one CoreBluetooth still
    // lists as connected) before they are discarded and the pump is rediscovered by scanning.
    // Two, so a single dropout that resolves itself does not pay for a rescan.
    private let staleFastPathThreshold = 2

    private var shouldAutoReconnect: Bool {
        connectStateLock.lock()
        defer { connectStateLock.unlock() }
        return !isDeactivated
    }

    private func setInFlightConnectGroup(_ group: TandemDispatchGroup?) {
        connectStateLock.lock()
        inFlightConnectGroup = group
        connectStateLock.unlock()
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

    func connect(_ peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        guard let manager else {
            logger.error("No CBCentralManager")
            return
        }

        stopScan()

        logger.info("Connecting to \(peripheral)")

        self.peripheral = peripheral
        connectCompletion = completion

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
        commandQueue.async {
            let error = self.connectIfNeeded()
            // Covers every way connectIfNeeded can fail, including the ones CoreBluetooth never
            // reports as a disconnect. A session that landed since the attempt gave up is live.
            if error != nil, !self.hasLiveSession {
                self.markLinkDown()
            }
            completion(error)
        }
    }

    /// Establishes a connection to the pump if one is not already up. MUST be called on
    /// `commandQueue`. Blocks (bounded by `connectTimeout`) until the connection is ready or the
    /// attempt fails/times out, returning nil on success and an error otherwise.
    ///
    /// The bounded wait is a `DispatchSemaphore.wait(timeout:)` (via TandemDispatchGroup): the
    /// timeout is intrinsic to the wait and needs no separate timer, so it cannot be starved by
    /// this queue being blocked — which is exactly the failure mode of the previous design.
    private func connectIfNeeded() -> Error? {
        if hasLiveSession {
            consecutiveConnectFailures = 0
            return nil
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

        let group = TandemDispatchGroup()
        group.enter()
        setInFlightConnectGroup(group)
        defer { setInFlightConnectGroup(nil) }

        // Per-attempt result holder so a late/stale connect callback from a previous attempt can
        // never clobber the result of the current one. Ordered after the wait by the semaphore.
        let resultBox = ConnectResultBox()
        let onConnect: (Error?) -> Void = { error in
            resultBox.error = error
            group.leave(Data())
        }

        if let peripheral {
            // Reuse the peripheral reference from a previous connection.
            connect(peripheral, completion: onConnect)
        } else if !rediscovering,
                  let peripheral = manager.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]).first
        {
            // Phone is already connected to the pump, but the app is not.
            connect(peripheral, completion: onConnect)
        } else if let identifier = pumpManager?.state.pumpState.peripheralUuid {
            // When rediscovering, this is the only path taken: cancelPeripheralConnection is
            // asynchronous, so the peripheral we just discarded can still be in the OS's
            // connected list for a moment, and reusing it from there would defeat the rescan.
            let scanStarted = startScan { result in
                guard result.bleIdentifier == identifier else {
                    return
                }
                self.logger.debug("Found pump, reconnecting! \(result.peripheral)")
                self.connect(result.peripheral, completion: onConnect)
            }
            if !scanStarted {
                return PumpCommError.pumpNotConnected
            }
        } else {
            logger.error("No identifier available to scan for...")
            return PumpCommError.pumpNotConnected
        }

        // Cancelled by cancelInFlightConnect() on disconnect/Bluetooth-off, or times out on its own.
        switch group.waitForOutcome(timeout: .now() + connectTimeout) {
        case .timedOut:
            logger.error("Connect attempt did not complete within \(connectTimeout)")
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
        if let peripheralManager {
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

        disconnect()
        pumpManager = nil
    }
}

extension TandemBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleBluetoothStateChange(central.state)
    }

    /// Split out of the delegate callback so it can be driven without a live `CBCentralManager`,
    /// whose `state` cannot be set on Apple platforms.
    func handleBluetoothStateChange(_ state: CBManagerState) {
        logger.info("\(String(describing: state.rawValue))")

        guard state == .poweredOn else {
            // Bluetooth went away (powered off / resetting / unauthorized). The
            // peripheral's CB operations are now invalid and their callbacks
            // won't fire, so cancel in-flight command waits to release any held
            // locks instead of waiting for the stack to come back.
            logger.info("Bluetooth not powered on; cancelling pending operations")
            cancelInFlightConnect()
            peripheralManager?.cancelPendingOperations()
            // No didDisconnectPeripheral arrives for those, so this is the only notice.
            markLinkDown()
            return
        }

        // So the UI stops blaming Bluetooth before the reconnect has even been attempted.
        pumpManager?.notifyDelegateStateUpdated()

        guard shouldAutoReconnect else {
            logger.info("Pump deactivated; not auto-reconnecting")
            return
        }

        ensureConnected { error in
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
        guard let completion = connectCompletion else {
            logger.warning("No connectCompletion...")
            return
        }

        self.peripheral = peripheral
        peripheralManager = TandemPeripheralManager(self, peripheral, pumpManager, completion)
        // The completion is now owned by the peripheral manager (fired at the end of
        // performInitialSetup, or on a setup error). Clear our reference so a later
        // unexpected disconnect takes the auto-reconnect path instead of firing this
        // now-stale completion.
        connectCompletion = nil

        peripheral.discoverServices(ServiceUUID.all)
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info(
            "Device disconnected, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
        )

        // Unblock any command thread parked on an in-flight BLE operation. The callbacks that
        // would normally release these waits (didWriteValueFor / didUpdateValueFor) will never
        // arrive now that the peripheral is gone, so without this a blocked write()/read() would
        // sit on the command queue until its bounded timeout. Cancelling lets it unwind promptly.
        // Also release any in-flight connect attempt (e.g. a disconnect mid-performInitialSetup),
        // which would otherwise block connectIfNeeded for the full connectTimeout.
        cancelInFlightConnect()
        peripheralManager?.cancelPendingOperations()
        markLinkDown()

        if let connectCompletion {
            connectCompletion(PumpCommError.pumpNotConnected)
            self.connectCompletion = nil

        } else if shouldAutoReconnect {
            logger.debug("Auto reconnect...")
            ensureConnected { error in
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

        // Complete the in-flight connect attempt promptly so connectIfNeeded returns an error
        // immediately rather than waiting out the full connectTimeout.
        if let connectCompletion {
            self.connectCompletion = nil
            connectCompletion(
                PumpCommError
                    .errorResponse(context: "Failed to connect: \(error?.localizedDescription ?? "unknown")")
            )
        }
    }
}
