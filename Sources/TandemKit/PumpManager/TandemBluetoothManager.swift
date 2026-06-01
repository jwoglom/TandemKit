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
        let localCompletion: (Error?) -> Void = { error in
            DispatchQueue.global(qos: .userInitiated).async {
                completion(error)
            }
        }

        if let peripheral, peripheral.state == .connected {
            localCompletion(nil)
            return
        }

        if let peripheral {
            // We've the peripheral reference to a previous connection
            // Just try to reconnect
            connect(peripheral) { error in
                localCompletion(error)
            }
            return
        }

        let connectedDevices = manager?.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]) ?? []
        if let peripheral = connectedDevices.first {
            // Phone is already connected, but the app is not
            connect(peripheral) { error in
                localCompletion(error)
            }
            return
        }

        guard let indentifier = pumpManager?.state.pumpState.peripheralUuid else {
            logger.error("No identifier available to scan for...")
            localCompletion(PumpCommError.pumpNotConnected)
            return
        }

        let scanStarted = startScan { result in
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
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            logger.warning("Pump found without name... \(peripheral)")
            return
        }

        scanCompletion?(TandemPumpScan(
            bleIdentifier: peripheral.identifier.uuidString,
            name: name,
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

        if let pumpManager {
            pumpManager.state.isConnected = true
            pumpManager.notifyDelegateStateUpdated()
        }

//        if forcedDisconnect {
//            forcedDisconnect = false
//            return
//        }

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
