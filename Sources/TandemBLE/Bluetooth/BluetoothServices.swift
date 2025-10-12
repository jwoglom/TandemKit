//
//  BluetoothServices.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//


import TandemCore

extension PeripheralManager.Configuration {
    static var tandemPeripheral: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                ServiceUUID.PUMP_SERVICE.cbUUID: AllPumpCharacteristicUUIDs.map { $0.cbUUID },
                ServiceUUID.DIS_SERVICE.cbUUID: DeviceInformationCharacteristics.map { $0.cbUUID },
                ServiceUUID.GENERIC_ATTRIBUTE_SERVICE.cbUUID: [CharacteristicUUID.SERVICE_CHANGED.cbUUID]
            ],
            notifyingCharacteristics: [
                ServiceUUID.PUMP_SERVICE.cbUUID: AllPumpCharacteristicUUIDs.map { $0.cbUUID },
                ServiceUUID.GENERIC_ATTRIBUTE_SERVICE.cbUUID: [CharacteristicUUID.SERVICE_CHANGED.cbUUID]
            ],
            valueUpdateMacros: [
                CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getAuthorizationCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.CONTROL_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getControlCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getControlStreamCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getCurrentStatusCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getHistoryLogCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getQualifyingEventsCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                CharacteristicUUID.SERVICE_CHANGED.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getServiceChangedCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                DeviceInformationCharacteristicUUID.manufacturerName.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getManufacturerNameCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                DeviceInformationCharacteristicUUID.modelNumber.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getModelNumberCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(BluetoothCmd(uuid: characteristic.uuid, value: value))
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                }
            ]
        )
    }
  }
