#if TANDEMKIT_VIRTUAL_PUMP
import CoreBluetooth
@testable import TandemKit

// Test files import both CoreBluetooth and TandemKit, so the names TandemKit shadows in a
// TANDEMKIT_VIRTUAL_PUMP build would be ambiguous here; pin them to TandemKit's.
typealias CBCentralManager = TandemKit.CBCentralManager
typealias CBCentralManagerDelegate = TandemKit.CBCentralManagerDelegate
typealias CBPeripheral = TandemKit.CBPeripheral
typealias CBPeripheralDelegate = TandemKit.CBPeripheralDelegate
typealias CBPeripheralState = TandemKit.CBPeripheralState
typealias CBService = TandemKit.CBService
typealias CBCharacteristic = TandemKit.CBCharacteristic
#endif
