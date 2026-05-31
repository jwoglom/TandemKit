import CoreBluetooth

class TandemPeripheralManager: NSObject {
    private let logger = TandemLogger(category: "TandemPeripheralManager")
    private let fallbackPairingCode = "000000"

    private var peripheral: CBPeripheral
    private let pumpManager: TandemPumpManager
    private let bluetoothManager: TandemBluetoothManager
    private var connectCompletion: ((Error?) -> Void)?

    private var readQueue: (TandemDispatchGroup, CBUUID)?
    private var writeQueue: (TandemDispatchGroup, UInt8)?
    private var commandLock: TandemDispatchGroup?
    private var currentTxId: UInt8 = 0

    private var authBuilder: JpakeAuthBuilder

    init(
        _ bluetoothManager: TandemBluetoothManager,
        _ peripheral: CBPeripheral,
        _ pumpManager: TandemPumpManager,
        _ connectCompletion: @escaping (Error?) -> Void
    ) {
        self.bluetoothManager = bluetoothManager
        self.peripheral = peripheral
        self.pumpManager = pumpManager
        self.connectCompletion = connectCompletion

        authBuilder = JpakeAuthBuilder.initializeWithPairingCode(pumpManager.state.pumpState.pincode ?? fallbackPairingCode)
        super.init()

        peripheral.delegate = self
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

        logger.debug("Writing message: \(message.description)")
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
            guard let result = writeQ.wait(timeout: .now() + .seconds(10)) else {
                logger.error("Timeout hit, no response from pump...")
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

                logger.debug("Waiting for more data...")
            }
        }

        logger.debug("Received message: \(response.message?.description ?? "nil")")
        return response.message
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
            let message = "Failed to didDiscoverCharacteristics: \(error.localizedDescription)"
            logger.error(message)
            connectCompletion?(PumpCommError.errorResponse(context: message))
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

        if let (writeQueue, writeOpCode) = writeQueue, data[2] == writeOpCode {
            writeQueue.leave(Data(data))
            return
        }

        if characteristic.uuid == FillTubingStateStreamResponse.props.characteristic,
           data[2] == FillTubingStateStreamResponse.props.opCode
        {
            let response = FillTubingStateStreamResponse(cargo: Data(data.dropFirst(5)))
            pumpManager.fillTubingStateStream.send(response)
            return
        }

        if characteristic.uuid == CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS {
            let events = QualifyingEvent.fromRawBytes(data)
            logger.error("Recieved qualifying events: \(events)")
            // TODO: Handle qualifying event...
            return
        }

        logger.warning("Not handler for message - data: \(data.hexadecimalString) characteristic: \(characteristic.uuid)")
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
    func performInitialSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            defer {
                JpakeAuthBuilder.clearInstance()
            }

            // Step 1: Requesting high priority
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

            // Step 2: Read model & manufacturer
            guard let _ = read(
                serviceUUID: ServiceUUID.DIS_SERVICE,
                characteristicUUID: CharacteristicUUID.DIS_MANUFACTURER_NAME
            ) else {
                logger.error("Failed to read Manufacturer...")
                bluetoothManager.disconnect()
                connectCompletion?(PumpCommError.noResponse)
                return
            }

            guard let _ = read(serviceUUID: ServiceUUID.DIS_SERVICE, characteristicUUID: CharacteristicUUID.DIS_MODEL_NUMBER)
            else {
                logger.error("Failed to read model number...")
                bluetoothManager.disconnect()
                connectCompletion?(PumpCommError.noResponse)
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
                        bluetoothManager.disconnect()
                        connectCompletion?(PumpCommError.noResponse)
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
                return
            }

            pumpManager.state.pumpState.timeSinceReset = response.pumpTimeSinceReset
            pumpManager.notifyDelegateStateUpdated()

            logger.info("Connected to pump!")
            connectCompletion?(nil)
        }
    }
}
