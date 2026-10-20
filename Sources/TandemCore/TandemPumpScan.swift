import CoreBluetooth

public struct TandemPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]?

    /// The unified pump simulator, fronting faketandem over CoreBluetooth, advertises the pump's
    /// name after this: `SIM Tandem Mobi 123`. A pump's name starts with its model.
    public static let simulatorNamePrefix = "SIM"

    public static func isSimulatorName(_ name: String) -> Bool {
        name.hasPrefix(simulatorNamePrefix)
    }
}
