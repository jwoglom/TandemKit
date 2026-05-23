import CoreBluetooth

class TandemBluetoothManager : NSObject {
    private let logger = TandemLogger(category: "TandemBluetoothManager")
    private let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)
    
    public var pumpManager: TandemPumpManager?

    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripheralManager: TandemPeripheralManager?
    
    private var scanCompletion: ((_ result: TandemPumpScan) -> Void)?
    private var connectCompletion: ((Error?) -> Void)?
    
    override init() {
        super.init()
        
        managerQueue.sync {
            self.manager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "com.jwoglom.TandemKit.bluetoothManager"]
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

        if !manager.isScanning {
            manager.stopScan()
        }

        scanCompletion = completion
        manager.scanForPeripherals(
            withServices: [ServiceUUID.PUMP_SERVICE],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        logger.info("Started scanning")
        return true
    }
    
    func connect(_ peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        guard let manager else {
            logger.error("No CBCentralManager")
            return
        }
        
        if manager.isScanning {
            manager.stopScan()
            scanCompletion = nil
        }

        logger.info("Connecting to \(peripheral)")

        self.peripheral = peripheral
        self.connectCompletion = completion
        
        manager.connect(peripheral)
    }
    
    func disconnect() {
        /*
         _ = try pumpComm.sendMessage(
             transport: transport,
             message: DisconnectPumpRequest(),
             expecting: DisconnectPumpResponse.self
         )
         */
    }
}

extension TandemBluetoothManager : CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("\(String(describing: central.state.rawValue))")
        guard central.state == .poweredOn else {
            return
        }

        if let peripheral = self.peripheral {
            logger.info("Reconnecting to restored state...")
            
            connect(peripheral) { error in
                if let error {
                    self.logger.error("Failed to auto reconnect...")
                }
            }
            return
        }
    }
    
    func centralManager(_ centralManager: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let peripheral = peripherals.first else {
            logger.warning("No restored peripherals!")
            return
        }

        self.peripheral = peripheral
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
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
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
        peripheralManager = TandemPeripheralManager(peripheral, pumpManager, completion)

        peripheral.discoverServices(ServiceUUID.all)
    }
    
    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info(
                "Device disconnected, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
            )

//        if forcedDisconnect {
//            forcedDisconnect = false
//            return
//        }

        if let peripheralManager {
            self.peripheralManager = nil
        }

        if let connectCompletion {
            connectCompletion(PumpCommError.pumpNotConnected)
            self.connectCompletion = nil

        } else {
            logger.debug("Auto reconnect...")
//            ensureConnected { error in
//                if let error = error {
//                    self.logger.warning("Failed to auto-reconnect: \(error)")
//                }
//            }
        }
    }
    
    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.info(
                "Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error?.localizedDescription ?? "No error")"
            )
    }
}
