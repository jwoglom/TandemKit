import Foundation

public class AlarmClearedHistoryLog: HistoryLog {
    public static let typeId = 28

    public let alarmId: UInt32

    public required init(cargo: Data) {
        alarmId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }
}
