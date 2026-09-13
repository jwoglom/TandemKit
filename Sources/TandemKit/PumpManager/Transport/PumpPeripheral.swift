import CoreBluetooth
import Foundation

/// One GATT peripheral as the driver sees it: everything is addressed by (service, characteristic)
/// UUID and carried as `Data`, so the same driver code runs over CoreBluetooth or over a socket to
/// a virtual pump. Callbacks arrive on the owning `PumpCentral`'s serial queue, never synchronously
/// from inside a request.
public protocol PumpPeripheral: AnyObject {
    var identifier: UUID { get }
    var name: String? { get }
    /// Reflects the live link state, updated before the matching central callback is delivered.
    var isConnected: Bool { get }
    var delegate: PumpPeripheralDelegate? { get set }

    /// Services found so far; populated by the time `didDiscoverServices` fires.
    var discoveredServices: [CBUUID] { get }

    func discoverServices(_ services: [CBUUID])
    func discoverCharacteristics(_ characteristics: [CBUUID], for service: CBUUID)
    func hasCharacteristic(_ characteristic: CBUUID, in service: CBUUID) -> Bool

    func readValue(for characteristic: CBUUID, in service: CBUUID)
    /// Always a write-with-response: `didWriteValueFor` follows once the pump has acknowledged it.
    func writeValue(_ data: Data, for characteristic: CBUUID, in service: CBUUID)
    func setNotifyValue(_ enabled: Bool, for characteristic: CBUUID, in service: CBUUID)
}

public protocol PumpPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: PumpPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: PumpPeripheral, didDiscoverCharacteristicsFor service: CBUUID, error: Error?)
    /// A read result or a notification; `value` is one ATT payload.
    func peripheral(_ peripheral: PumpPeripheral, didUpdateValueFor characteristic: CBUUID, value: Data?, error: Error?)
    func peripheral(_ peripheral: PumpPeripheral, didWriteValueFor characteristic: CBUUID, error: Error?)
    func peripheral(_ peripheral: PumpPeripheral, didUpdateNotificationStateFor characteristic: CBUUID, error: Error?)
}
