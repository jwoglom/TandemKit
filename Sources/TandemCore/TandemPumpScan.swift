import CoreBluetooth

public struct TandemPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]?

    /// A simulator says so in its name, in either spelling: the unified pump simulator, fronting
    /// faketandem over CoreBluetooth, advertises `Tandem Mobi Simulator 123`. A pump's name is its
    /// model and serial.
    public static func isSimulatorName(_ name: String) -> Bool {
        name.contains("SIM") || name.range(of: "simulator", options: .caseInsensitive) != nil
    }
}
