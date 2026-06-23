import CoreBluetooth

/// Heap box carrying a single connect attempt's result from its (cross-thread) completion handler
/// back to the waiting connectIfNeeded. The DispatchSemaphore in TandemDispatchGroup provides the
/// happens-before ordering between the write here and the read after `wait`.
private final class ConnectResultBox {
    var error: Error?
}

class TandemBluetoothManager: NSObject {
    static let centralManagerRestoreIdentifier = "com.jwoglom.TandemKit.CentralManager"

    private let logger = TandemLogger(category: "TandemBluetoothManager")
    private let managerQueue = DispatchQueue(label: "com.jwoglom.TandemKit.bluetoothManagerQueue", qos: .unspecified)

    public var pumpManager: TandemPumpManager?

    private(set) var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripheralManager: TandemPeripheralManager?

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

    // Pump-communications-suspended gate (mirrors the Android app's PauseReason.SUSPEND_COMM).
    // When the pump reports bit 19 set, command jobs must not write to the pump. The gate is an
    // NSCondition so a command job waiting in write() (on commandQueue) is woken the instant resume
    // is signalled, while suspend/resume themselves never block. The wait in write() is hard-bounded
    // (commsSuspendMaxWait) so a stuck suspend can never wedge a bolus or the loop; ANY (re)connection
    // force-resumes via ensureCommunicationsNotSuspended(), and disconnect releases the gate.
    private let commsSuspendedCondition = NSCondition()
    private var _commsSuspended = false
    private let commsSuspendMaxWait: TimeInterval = 30

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

    /// Suspends or resumes pump communications based on the pumpCommunicationsSuspended qualifying
    /// event. Called from the notification path; must never block. Mirrors Android's
    /// toggleCommunication(bit19): set-while-clear suspends, clear-while-set resumes.
    func toggleCommunicationsSuspended(_ suspended: Bool) {
        commsSuspendedCondition.lock()
        let changed = _commsSuspended != suspended
        if changed {
            _commsSuspended = suspended
            if !suspended {
                commsSuspendedCondition.broadcast()
            }
        }
        commsSuspendedCondition.unlock()
        if changed {
            logger.info("Pump communications \(suspended ? "suspended" : "resumed")")
        }
    }

    /// Force-resumes pump communications. Invoked on every (re)connection so a suspend state can
    /// never survive a reconnect and wedge the command pipeline (mirrors Android's
    /// ensureCommunicationsNotSuspended()).
    func ensureCommunicationsNotSuspended() {
        toggleCommunicationsSuspended(false)
    }

    /// Blocks the calling command job (on commandQueue) while communications are suspended, bounded
    /// by commsSuspendMaxWait. Returns true if it is safe to proceed (resumed, or never suspended,
    /// or the bound elapsed), which it always does — the bound guarantees a command can never hang
    /// indefinitely on a stuck suspend.
    private func awaitCommunicationsResumed() {
        commsSuspendedCondition.lock()
        defer { commsSuspendedCondition.unlock() }
        guard _commsSuspended else { return }
        let deadline = Date().addingTimeInterval(commsSuspendMaxWait)
        while _commsSuspended {
            if !commsSuspendedCondition.wait(until: deadline) {
                logger.error("Communications still suspended after \(commsSuspendMaxWait)s; proceeding")
                return
            }
        }
    }

    override init() {
        super.init()

        managerQueue.sync {
            self.manager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: TandemBluetoothManager.centralManagerRestoreIdentifier]
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

    func write(message: Message, expecting: Message.Type, maxChunkSize: Int? = nil) -> Message? {
        guard let peripheralManager else {
            logger.error("No peripheralManager -> Not connected...")
            return nil
        }

        awaitCommunicationsResumed()

        return peripheralManager.write(message: message, expecting: expecting, maxChunkSize: maxChunkSize)
    }

    /// Runs `completion` as a serialized command job: the pump is connected if necessary, then
    /// `completion` runs on `commandQueue` so its (blocking) writes are serialized against every
    /// other command and against connection setup. `completion` always runs exactly once, with a
    /// non-nil error if the connection could not be established within `connectTimeout`.
    func ensureConnected(completion: @escaping (Error?) -> Void) {
        commandQueue.async {
            let error = self.connectIfNeeded()
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
        if let peripheral, peripheral.state == .connected, peripheralManager != nil {
            return nil
        }

        guard let manager else {
            return PumpCommError.pumpNotConnected
        }
        guard manager.state == .poweredOn else {
            logger.error("Bluetooth not powered on (state \(manager.state.rawValue)); cannot connect")
            return PumpCommError.pumpNotConnected
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
        } else if let peripheral = manager.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]).first {
            // Phone is already connected to the pump, but the app is not.
            connect(peripheral, completion: onConnect)
        } else if let identifier = pumpManager?.state.pumpState.peripheralUuid {
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
        if group.wait(timeout: .now() + connectTimeout) == nil {
            logger.error("Connect attempt did not complete within \(connectTimeout)")
            return PumpCommError.pumpNotConnected
        }
        return resultBox.error
    }

    func disconnect() {
        if let peripheralManager {
            _ = peripheralManager.write(message: DisconnectPumpRequest(), expecting: DisconnectPumpResponse.self)
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
}

extension TandemBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("\(String(describing: central.state.rawValue))")

        guard central.state == .poweredOn else {
            // Bluetooth went away (powered off / resetting / unauthorized). The
            // peripheral's CB operations are now invalid and their callbacks
            // won't fire, so cancel in-flight command waits to release any held
            // locks instead of waiting for the stack to come back.
            logger.info("Bluetooth not powered on; cancelling pending operations")
            cancelInFlightConnect()
            peripheralManager?.cancelPendingOperations()
            ensureCommunicationsNotSuspended()
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

        ensureCommunicationsNotSuspended()

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
        // Release the comms-suspend gate so a job parked in write() unwinds; the reconnect path
        // re-establishes a clean (resumed) state.
        ensureCommunicationsNotSuspended()

        if let pumpManager {
            pumpManager.state.isConnected = false
            pumpManager.notifyDelegateStateUpdated()
        }

        peripheralManager = nil

        if let connectCompletion {
            connectCompletion(PumpCommError.pumpNotConnected)
            self.connectCompletion = nil

        } else {
            logger.debug("Auto reconnect...")
            ensureConnected { error in
                if let error = error {
                    self.logger.warning("Failed to auto-reconnect: \(error)")
                }
            }
        }
    }

    func centralManager(_: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        logger.info("Restoring CB state with \(restored.count) peripheral(s)")

        let identifier = pumpManager?.state.pumpState.peripheralUuid
        guard let peripheral = restored.first(where: { identifier == nil || $0.identifier.uuidString == identifier })
        else {
            logger.info("No restorable pump peripheral in CB state")
            return
        }

        self.peripheral = peripheral

        guard let pumpManager else {
            logger.warning("Restored peripheral but no pumpManager...")
            return
        }

        // If the restored peripheral is already connected, re-wire the peripheral manager exactly as
        // didConnect would so the existing command/notification path keeps working across relaunch.
        // Otherwise leave it for centralManagerDidUpdateState / didConnect to reconnect; the stored
        // peripheral reference above is enough for connectIfNeeded to reuse it.
        if peripheral.state == .connected {
            peripheralManager = TandemPeripheralManager(self, peripheral, pumpManager) { error in
                if let error {
                    self.logger.warning("Restored connection setup failed: \(error)")
                }
            }
            connectCompletion = nil
            peripheral.discoverServices(ServiceUUID.all)
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
