import Foundation

public class VersionsAHistoryLog: HistoryLog {
    public static let typeId = 307

    public let armPartNumber: UInt32
    public let armSwVersion: UInt32
    public let blePartNumber: UInt32
    public let bleSwVersion: UInt32

    public required init(cargo: Data) {
        armPartNumber = Bytes.readUint32(cargo, 10)
        armSwVersion = Bytes.readUint32(cargo, 14)
        blePartNumber = Bytes.readUint32(cargo, 18)
        bleSwVersion = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, armPartNumber: UInt32, armSwVersion: UInt32, blePartNumber: UInt32, bleSwVersion: UInt32) {
        let payload = VersionsAHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            armPartNumber: armPartNumber,
            armSwVersion: armSwVersion,
            blePartNumber: blePartNumber,
            bleSwVersion: bleSwVersion
        )
        self.armPartNumber = armPartNumber
        self.armSwVersion = armSwVersion
        self.blePartNumber = blePartNumber
        self.bleSwVersion = bleSwVersion
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, armPartNumber: UInt32, armSwVersion: UInt32, blePartNumber: UInt32, bleSwVersion: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(armPartNumber),
                Bytes.toUint32(armSwVersion),
                Bytes.toUint32(blePartNumber),
                Bytes.toUint32(bleSwVersion)
            )
        )
    }

    override public var description: String {
        "VersionsAHistoryLog(cargo=\(cargo.hexadecimalString), armPartNumber=\(armPartNumber), armSwVersion=\(armSwVersion), blePartNumber=\(blePartNumber), bleSwVersion=\(bleSwVersion))"
    }
}
