public struct TandemPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: any PumpPeripheral
    public let advertisementData: [String: Any]?
}
