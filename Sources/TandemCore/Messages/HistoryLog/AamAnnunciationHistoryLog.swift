import Foundation

/// Written when the pump annunciates an active, unacknowledged alert, alarm or CGM alert: at activation, then about every 5 minutes.
/// Provisional name; bytes 11, 12-13, 18 and 19 are not understood. See https://github.com/jwoglom/pumpX2/issues/147.
public class AamAnnunciationHistoryLog: HistoryLog {
    public static let typeId = 434

    public enum AamCategory: Int {
        case alert = 3
        case alarm = 4
        case cgmAlert = 6
    }

    public let categoryId: Int
    public let unknown11: Int
    public let unknown12: Int
    /// Id in the category's id space: AlertResponseType, AlarmResponseType, or the CGM alert id. 0 is LOW_INSULIN_ALERT.
    public let notificationId: UInt32
    public let unknown18: Int
    public let unknown19: Int

    public required init(cargo: Data) {
        let start = cargo.startIndex
        categoryId = Int(cargo[start + 10])
        unknown11 = Int(cargo[start + 11])
        unknown12 = Bytes.readShort(cargo, 12)
        notificationId = Bytes.readUint32(cargo, 14)
        unknown18 = Int(cargo[start + 18])
        unknown19 = Int(cargo[start + 19])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        categoryId: Int,
        unknown11: Int,
        unknown12: Int,
        notificationId: UInt32,
        unknown18: Int,
        unknown19: Int
    ) {
        let payload = AamAnnunciationHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            categoryId: categoryId,
            unknown11: unknown11,
            unknown12: unknown12,
            notificationId: notificationId,
            unknown18: unknown18,
            unknown19: unknown19
        )
        self.categoryId = categoryId
        self.unknown11 = unknown11
        self.unknown12 = unknown12
        self.notificationId = notificationId
        self.unknown18 = unknown18
        self.unknown19 = unknown19
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        categoryId: Int,
        unknown11: Int,
        unknown12: Int,
        notificationId: UInt32,
        unknown18: Int,
        unknown19: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstByteLittleEndian(categoryId),
                Bytes.firstByteLittleEndian(unknown11),
                Bytes.firstTwoBytesLittleEndian(unknown12),
                Bytes.toUint32(notificationId),
                Bytes.firstByteLittleEndian(unknown18),
                Bytes.firstByteLittleEndian(unknown19)
            )
        )
    }

    public var category: AamCategory? {
        AamCategory(rawValue: categoryId)
    }

    public var alertResponseType: AlertStatusResponse.AlertResponseType? {
        guard category == .alert else { return nil }
        return AlertStatusResponse.AlertResponseType(rawValue: Int(notificationId))
    }

    public var alarmResponseType: AlarmStatusResponse.AlarmResponseType? {
        guard category == .alarm else { return nil }
        return AlarmStatusResponse.AlarmResponseType(rawValue: Int(notificationId))
    }

    override public var description: String {
        "AamAnnunciationHistoryLog(cargo=\(cargo.hexadecimalString), category=\(String(describing: category)), categoryId=\(categoryId), notificationId=\(notificationId), unknown11=\(unknown11), unknown12=\(unknown12), unknown18=\(unknown18), unknown19=\(unknown19))"
    }
}
