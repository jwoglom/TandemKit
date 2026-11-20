import Foundation

public class ReminderDismissedHistoryLog: HistoryLog {
    public static let typeId = 29

    public let reminderId: UInt32

    public required init(cargo: Data) {
        reminderId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, reminderId: UInt32) {
        let payload = ReminderDismissedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            reminderId: reminderId
        )
        self.reminderId = reminderId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, reminderId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(reminderId)
            )
        )
    }

    override public var description: String {
        "ReminderDismissedHistoryLog(cargo=\(cargo.hexadecimalString), reminderId=\(reminderId))"
    }
}
