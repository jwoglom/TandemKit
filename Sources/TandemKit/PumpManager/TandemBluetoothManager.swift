import CoreBluetooth

/// Heap box carrying a single connect attempt's result from its (cross-thread) completion handler
/// back to the waiting connectIfNeeded. The DispatchSemaphore in TandemDispatchGroup provides the
/// happens-before ordering between the write here and the read after `wait`.
private final class ConnectResultBox {
    var error: Error?
}

class TandemBluetoothManager: NSObject {
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

    // Count of connect attempts that have failed back-to-back without an intervening success.
    // Only ever mutated from connectIfNeeded (which runs serialized on commandQueue), so it
    // needs no extra locking. Once it reaches connectEscalationThreshold we stop retrying the
    // cached peripheral — which may be a stale/wedged object — and force a fresh scan instead.
    private var consecutiveConnectFailures = 0
    private let connectEscalationThreshold = 3

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

        // If a connect for a *different* peripheral object is still outstanding, cancel it
        // first. A re-scan hands back a fresh CBPeripheral instance for the same device
        // (same identifier, new object), and CB keeps the previous object's connect pending
        // forever — so without this, retries accumulate competing connect requests against
        // the same pump and none complete.
        if let existing = self.peripheral, existing !== peripheral {
            manager.cancelPeripheralConnection(existing)
        }

        logger.info("Connecting to \(peripheral)")

        self.peripheral = peripheral
        connectCompletion = completion

        manager.connect(peripheral)
    }

    /// Tears down whatever scan / connect attempt is currently outstanding.
    ///
    /// CoreBluetooth's `connect()` has no timeout of its own — once issued it stays pending
    /// indefinitely until it succeeds, fails, or is explicitly cancelled. So when our own
    /// `connectTimeout` fires we must cancel the underlying request, otherwise the wedged
    /// connect lingers in the BLE stack and blocks every subsequent attempt (observed as a
    /// multi-hour inability to reconnect to a pump sitting inches away).
    private func cancelPendingConnect() {
        guard let manager else { return }
        if manager.isScanning {
            manager.stopScan()
        }
        if let peripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
    }

    func write(message: Message, expecting: Message.Type, maxChunkSize: Int? = nil) -> Message? {
        guard let peripheralManager else {
            logger.error("No peripheralManager -> Not connected...")
            return nil
        }

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

        // After repeated back-to-back failures the cached peripheral object is likely stale or
        // wedged (re-issuing connect() on it keeps timing out). Drop and cancel it so the
        // strategy below falls through to a fresh scan, which produces a new peripheral object —
        // the same move that recovers the connection when done manually.
        if consecutiveConnectFailures >= connectEscalationThreshold, let stale = peripheral {
            logger.warning(
                "Escalating reconnect after \(consecutiveConnectFailures) failures: dropping cached peripheral and rescanning"
            )
            manager.cancelPeripheralConnection(stale)
            peripheral = nil
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
            // Cancel the still-pending CoreBluetooth connect so it does not linger and block
            // future attempts; CB never times it out on its own.
            cancelPendingConnect()
            consecutiveConnectFailures += 1
            return PumpCommError.pumpNotConnected
        }

        if let error = resultBox.error {
            consecutiveConnectFailures += 1
            return error
        }

        consecutiveConnectFailures = 0
        return nil
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
