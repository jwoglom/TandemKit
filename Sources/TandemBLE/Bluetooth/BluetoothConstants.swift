#if canImport(CoreBluetooth)
import Foundation

/// Constants related to Tandem pump Bluetooth connections.
/// Mirrors `BluetoothConstants` from pumpx2.
enum BluetoothConstants {
    /// Prefix used by Tandem pumps when advertising over BLE.
    static let deviceNameTSlimX2 = "tslim X2"

    /// Returns true if the provided Bluetooth device name matches a known Tandem pump.
    static func isTandemBluetoothDevice(_ name: String?) -> Bool {
        guard let name = name else { return false }
        return name.hasPrefix(deviceNameTSlimX2)
    }
}
#endif
