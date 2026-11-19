import Foundation

public class CgmLgaSettingsHistoryLog: HistoryLog {
    public static let typeId = 166

    public let alertLevel: Int
    public let repeatDuration: Int
    public let isEnabled: Bool
    public let modifiedField: Int

    public required init(cargo: Data) {
        alertLevel = Bytes.readShort(cargo, 10)
        repeatDuration = Bytes.readShort(cargo, 12)
        isEnabled = cargo[14] != 0
        modifiedField = Bytes.readShort(cargo, 16)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertLevel: Int,
        repeatDuration: Int,
        isEnabled: Bool,
        modifiedField: Int
    ) {
        let payload = CgmLgaSettingsHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            alertLevel: alertLevel,
            repeatDuration: repeatDuration,
            isEnabled: isEnabled,
            modifiedField: modifiedField
        )
        self.alertLevel = alertLevel
        self.repeatDuration = repeatDuration
        self.isEnabled = isEnabled
        self.modifiedField = modifiedField
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertLevel: Int,
        repeatDuration: Int,
        isEnabled: Bool,
        modifiedField: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(alertLevel),
                Bytes.firstTwoBytesLittleEndian(repeatDuration),
                Data([isEnabled ? 1 : 0, 0]),
                Bytes.firstTwoBytesLittleEndian(modifiedField)
            )
        )
    }

    public enum ModifiedField: Int {
        case enable = 0
        case threshold = 1
        case duration = 2
        case invalid = 3
    }

    public var modifiedFieldEnum: ModifiedField {
        ModifiedField(rawValue: modifiedField) ?? .invalid
    }

    override public var description: String {
        "CgmLgaSettingsHistoryLog(cargo=\(cargo.hexadecimalString), alertLevel=\(alertLevel), repeatDuration=\(repeatDuration), isEnabled=\(isEnabled), modifiedField=\(modifiedField))"
    }
}
