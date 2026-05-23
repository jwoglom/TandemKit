import CoreBluetooth

class TandemPeripheralManager: NSObject {
    private let logger = TandemLogger(category: "TandemPeripheralManager")
    
    private var peripheral: CBPeripheral
    private let pumpManager: TandemPumpManager
    private var connectCompletion: ((Error?) -> Void)?
    
    private var readQueue: (TandemDispatchGroup, CBUUID)?
    
    init(_ peripheral: CBPeripheral, _ pumpManager: TandemPumpManager, _ connectCompletion: @escaping (Error?) -> Void) {
        self.peripheral = peripheral
        self.pumpManager = pumpManager
        self.connectCompletion = connectCompletion
        super.init()

        peripheral.delegate = self
    }
    
    func read(service serviceUUID: CBUUID, characteristic characteristicUUID: CBUUID) -> Data? {
        guard let characteristic = getCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            return nil
        }

        let readQ = TandemDispatchGroup()
        readQ.enter()
        readQueue = (readQ, characteristicUUID)
        peripheral.readValue(for: characteristic)

        defer {
            readQueue = nil
        }

        return readQ.wait(timeout: .now() + .seconds(10))
    }
    
    func startNotify(service serviceUUID: CBUUID, characteristic characteristicUUID: CBUUID) {
        guard let characteristic = getCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            return
        }

        peripheral.setNotifyValue(true, for: characteristic)
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
            connectCompletion?(PumpCommError.errorResponse(context: "Failed to discoverServices: \(error.localizedDescription)"))
            return
        }
        
        self.peripheral = peripheral
        
        guard let pumpService = peripheral.services?.first(where: { $0.uuid == ServiceUUID.PUMP_SERVICE }) else {
            logger.error("No pump service found...")
            connectCompletion?(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.PUMP_SERVICE)"))
            return
        }
        peripheral.discoverCharacteristics(CharacteristicUUID.allPumpCharacteristics, for: pumpService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error = error {
            logger.error("Failed to didDiscoverCharacteristics: \(error.localizedDescription)")
            connectCompletion?(PumpCommError.errorResponse(context: "Failed to didDiscoverCharacteristics: \(error.localizedDescription)"))
            return
        }
        
        self.peripheral = peripheral
        
        if service.uuid == ServiceUUID.PUMP_SERVICE {
            guard let deviceInfoService = peripheral.services?.first(where: { $0.uuid == ServiceUUID.DIS_SERVICE }) else {
                logger.error("No device info service found...")
                connectCompletion?(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.DIS_SERVICE)"))
                return
            }
            peripheral.discoverCharacteristics(CharacteristicUUID.allDeviceInfoCharacteristics, for: deviceInfoService)
            return
        }
        
        if service.uuid == ServiceUUID.DIS_SERVICE {
            guard let attributeService = peripheral.services?.first(where: { $0.uuid == ServiceUUID.GENERIC_ATTRIBUTE_SERVICE }) else {
                logger.error("No attribute service found...")
                connectCompletion?(PumpCommError.errorResponse(context: "No service: \(ServiceUUID.GENERIC_ATTRIBUTE_SERVICE)"))
                return
            }
            peripheral.discoverCharacteristics([CharacteristicUUID.SERVICE_CHANGED], for: attributeService)
            return
        }
        
        logger.info("Discovery completed!")
        performInitialSetup()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            logger.error("Received error in didUpdateValueFor: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            logger.warning("Empty data -> char: \(characteristic.uuid.uuidString), service: \(characteristic.service?.uuid.uuidString ?? "No service")")
            return
        }
        
        if let (readQueue, readCharacteristic) = readQueue, readCharacteristic == characteristic.uuid {
            logger.debug("Read data: \(data.hexadecimalString), characteristic: \(characteristic.uuid.uuidString)")
            readQueue.leave(Data(data))
            return
        }
        
        logger.warning("Not handler for message - data: \(data.hexadecimalString), characteristic: \(characteristic.uuid.uuidString)")
    }
}

extension TandemPeripheralManager {
    internal func performInitialSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Get device data -> Manufacturer & model number
            guard let manufacturer = read(
                service: ServiceUUID.DIS_SERVICE,
                characteristic: CharacteristicUUID.DIS_MANUFACTURER_NAME
            ) else {
                logger.error("Failed to read manufacturer...")
                connectCompletion?(PumpCommError.errorResponse(context: "No manufacturer: \(CharacteristicUUID.DIS_MANUFACTURER_NAME)"))
                return
            }
            
            guard let model = read(
                service: ServiceUUID.DIS_SERVICE,
                characteristic: CharacteristicUUID.DIS_MODEL_NUMBER
            ) else {
                logger.error("Failed to read model name...")
                connectCompletion?(PumpCommError.errorResponse(context: "No model name: \(CharacteristicUUID.DIS_MODEL_NUMBER)"))
                return
            }
            
            // Step 2: Start notify
            for (service, characteristic) in CharacteristicUUID.notificationCharacteristics {
                startNotify(
                    service: service,
                    characteristic: characteristic
                )
            }
            
            // Step 3: Authenticate
        }
    }
}
