import Foundation

/// Hourly Mobi battery snapshot (jwoglom/pumpX2#149). Provisional name; `unknown*` fields are unidentified.
/// `lipoMv` is millivolts; `unknown16` is signed.
public class BatteryHourlyHistoryLog: HistoryLog {
    public static let typeId = 271

    public let currentBatteryIbc: Int
    public let unknown12: Int
    public let lipoMv: Int
    public let unknown16: Int
    public let unknown18: Int
    public let unknown20: Int
    public let unknown22: Int
    public let unknown24: Int

    public required init(cargo: Data) {
        currentBatteryIbc = Bytes.readShort(cargo, 10)
        unknown12 = Bytes.readShort(cargo, 12)
        lipoMv = Bytes.readShort(cargo, 14)
        unknown16 = Int(Int16(bitPattern: UInt16(Bytes.readShort(cargo, 16))))
        unknown18 = Bytes.readShort(cargo, 18)
        unknown20 = Bytes.readShort(cargo, 20)
        unknown22 = Bytes.readShort(cargo, 22)
        unknown24 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, currentBatteryIbc: Int, unknown12: Int, lipoMv: Int, unknown16: Int, unknown18: Int, unknown20: Int, unknown22: Int, unknown24: Int) {
        let payload = BatteryHourlyHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentBatteryIbc: currentBatteryIbc,
            unknown12: unknown12,
            lipoMv: lipoMv,
            unknown16: unknown16,
            unknown18: unknown18,
            unknown20: unknown20,
            unknown22: unknown22,
            unknown24: unknown24
        )
        self.currentBatteryIbc = currentBatteryIbc
        self.unknown12 = unknown12
        self.lipoMv = lipoMv
        self.unknown16 = unknown16
        self.unknown18 = unknown18
        self.unknown20 = unknown20
        self.unknown22 = unknown22
        self.unknown24 = unknown24
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, currentBatteryIbc: Int, unknown12: Int, lipoMv: Int, unknown16: Int, unknown18: Int, unknown20: Int, unknown22: Int, unknown24: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(currentBatteryIbc),
                Bytes.firstTwoBytesLittleEndian(unknown12),
                Bytes.firstTwoBytesLittleEndian(lipoMv),
                Bytes.firstTwoBytesLittleEndian(unknown16),
                Bytes.firstTwoBytesLittleEndian(unknown18),
                Bytes.firstTwoBytesLittleEndian(unknown20),
                Bytes.firstTwoBytesLittleEndian(unknown22),
                Bytes.firstTwoBytesLittleEndian(unknown24)
            )
        )
    }

    override public var description: String {
        "BatteryHourlyHistoryLog(cargo=\(cargo.hexadecimalString), currentBatteryIbc=\(currentBatteryIbc), unknown12=\(unknown12), lipoMv=\(lipoMv), unknown16=\(unknown16), unknown18=\(unknown18), unknown20=\(unknown20), unknown22=\(unknown22), unknown24=\(unknown24))"
    }
}
