import Foundation

public class DailyStatusHistoryLog: HistoryLog {
    public static let typeId = 313

    public let sensorType: Int
    public let userMode: Int
    public let pumpControlState: Int

    public required init(cargo: Data) {
        sensorType = Int(cargo[11])
        userMode = Int(cargo[12])
        pumpControlState = Int(cargo[13])
        super.init(cargo: cargo)
    }
}
