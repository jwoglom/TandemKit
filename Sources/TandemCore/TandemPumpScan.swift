import CoreBluetooth

public struct TandemPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]?

    /// The unified pump simulator, fronting faketandem over CoreBluetooth, advertises the pump's
    /// name with `SIM` in place of the serial: `Tandem Mobi SIM`. A pump's name ends in its serial.
    public static let simulatorNameSuffix = " SIM"

    public static func isSimulatorName(_ name: String) -> Bool {
        name.hasSuffix(simulatorNameSuffix)
    }
}
