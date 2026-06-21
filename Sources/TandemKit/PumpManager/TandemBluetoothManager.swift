import CoreBluetooth

class TandemBluetoothManager: NSObject {
    private let logger = TandemLogger(category: "TandemBluetoothManager")
    private let managerQueue = DispatchQueue(label: "com.jwoglom.TandemKit.bluetoothManagerQueue", qos: .unspecified)

    public var pumpManager: TandemPumpManager?

    private(set) var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripheralManager: TandemPeripheralManager?

    private var scanCompletion: ((_ result: TandemPumpScan) -> Void)?
    private var connectCompletion: ((Error?) -> Void)?
    private let connectionQueue = DispatchQueue(label: "com.jwoglom.TandemKit.ensureConnected")
    private let connectionSemaphore = DispatchSemaphore(value: 1)
    // Upper bound on how long a single ensureConnected attempt may hold the
    // connection lock. Guarantees the semaphore is always released even if no
    // BLE scan result or connection callback ever arrives (e.g. pump out of
    // range), preventing both a permanent deadlock of future attempts and the
    // unbalanced-semaphore trap on deallocation.
    private let connectionAttemptTimeout: DispatchTimeInterval = .seconds(30)

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

    func write(message: Message, expecting: Message.Type, maxChunkSize: Int? = nil) -> Message? {
        guard let peripheralManager else {
            logger.error("No peripheralManager -> Not connected...")
            return nil
        }

        return peripheralManager.write(message: message, expecting: expecting, maxChunkSize: maxChunkSize)
    }

    func ensureConnected(completion: @escaping (Error?) -> Void) {
        connectionQueue.async {
            // Wait until previous ensureConnected calls have been completed
            self.connectionSemaphore.wait()

            // localCompletion must run exactly once so that connectionSemaphore
            // is signaled exactly once. BLE callbacks below may fire more than
            // once (duplicate scan results) or never (pump never discovered), so
            // guard with a fire-once flag evaluated on the serial connectionQueue.
            var didComplete = false
            let localCompletion: (Error?) -> Void = { error in
                self.connectionQueue.async {
                    guard !didComplete else { return }
                    didComplete = true

                    self.connectCompletion = nil

                    DispatchQueue.global(qos: .userInitiated).async {
                        completion(error)
                        self.connectionSemaphore.signal()
                    }
                }
            }

            // Safety net: always release the lock after a bounded interval, even
            // if no scan/connection callback ever fires. The fire-once guard makes
            // this a no-op when the attempt has already completed.
            self.connectionQueue.asyncAfter(deadline: .now() + self.connectionAttemptTimeout) {
                localCompletion(PumpCommError.pumpNotConnected)
            }

            if let peripheral = self.peripheral, peripheral.state == .connected {
                localCompletion(nil)
                return
            }

            if let peripheral = self.peripheral {
                // We've the peripheral reference to a previous connection
                // Just try to reconnect
                self.connect(peripheral) { error in
                    localCompletion(error)
                }
                return
            }

            let connectedDevices = self.manager?.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]) ?? []
            if let peripheral = connectedDevices.first {
                // Phone is already connected, but the app is not
                self.connect(peripheral) { error in
                    localCompletion(error)
                }
                return
            }

            guard let indentifier = self.pumpManager?.state.pumpState.peripheralUuid else {
                self.logger.error("No identifier available to scan for...")
                localCompletion(PumpCommError.pumpNotConnected)
                return
            }

            let scanStarted = self.startScan { result in
                guard result.bleIdentifier == indentifier else {
                    return
                }

                self.logger.debug("Found pump, reconnecting! \(result.peripheral)")
                self.connect(result.peripheral) { error in
                    localCompletion(error)
                }
            }

            if !scanStarted {
                localCompletion(PumpCommError.pumpNotConnected)
                return
            }
        }
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

        peripheral.discoverServices(ServiceUUID.all)
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info(
            "Device disconnected, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
        )

        // Unblock any command thread parked on an in-flight BLE operation. The
        // callbacks that would normally release these waits (didWriteValueFor /
        // didUpdateValueFor) will never arrive now that the peripheral is gone,
        // so without this a blocked write()/read() would hold writeSemaphore and
        // the owning ensureConnected closure would hold connectionSemaphore until
        // the Bluetooth stack power-cycles. Cancelling lets those locks unwind.
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
    }
}
