import Foundation

/// Battery snapshot written when CurrentBatteryV2Response.chargingStatus goes 0 to 1 (jwoglom/pumpX2#149).
/// Provisional name; `unknown*` fields are unidentified. `lipoMv` is millivolts.
public class ChargingStartedHistoryLog: HistoryLog {
    public static let typeId = 34

    public let currentBatteryAbc: Int
    public let unknown12: Int
    public let unknown14: Int
    public let currentBatteryIbc: Int
    public let unknown18: Int
    public let lipoMv: Int
    public let unknown22: Int
    public let unknown24: Int

    public required init(cargo: Data) {
        currentBatteryAbc = Bytes.readShort(cargo, 10)
        unknown12 = Bytes.readShort(cargo, 12)
        unknown14 = Bytes.readShort(cargo, 14)
        currentBatteryIbc = Bytes.readShort(cargo, 16)
        unknown18 = Bytes.readShort(cargo, 18)
        lipoMv = Bytes.readShort(cargo, 20)
        unknown22 = Bytes.readShort(cargo, 22)
        unknown24 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, currentBatteryAbc: Int, unknown12: Int, unknown14: Int, currentBatteryIbc: Int, unknown18: Int, lipoMv: Int, unknown22: Int, unknown24: Int) {
        let payload = ChargingStartedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentBatteryAbc: currentBatteryAbc,
            unknown12: unknown12,
            unknown14: unknown14,
            currentBatteryIbc: currentBatteryIbc,
            unknown18: unknown18,
            lipoMv: lipoMv,
            unknown22: unknown22,
            unknown24: unknown24
        )
        self.currentBatteryAbc = currentBatteryAbc
        self.unknown12 = unknown12
        self.unknown14 = unknown14
        self.currentBatteryIbc = currentBatteryIbc
        self.unknown18 = unknown18
        self.lipoMv = lipoMv
        self.unknown22 = unknown22
        self.unknown24 = unknown24
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, currentBatteryAbc: Int, unknown12: Int, unknown14: Int, currentBatteryIbc: Int, unknown18: Int, lipoMv: Int, unknown22: Int, unknown24: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(currentBatteryAbc),
                Bytes.firstTwoBytesLittleEndian(unknown12),
                Bytes.firstTwoBytesLittleEndian(unknown14),
                Bytes.firstTwoBytesLittleEndian(currentBatteryIbc),
                Bytes.firstTwoBytesLittleEndian(unknown18),
                Bytes.firstTwoBytesLittleEndian(lipoMv),
                Bytes.firstTwoBytesLittleEndian(unknown22),
                Bytes.firstTwoBytesLittleEndian(unknown24)
            )
        )
    }

    public var description: String {
        "ChargingStartedHistoryLog(cargo=\(cargo.hexadecimalString), currentBatteryAbc=\(currentBatteryAbc), unknown12=\(unknown12), unknown14=\(unknown14), currentBatteryIbc=\(currentBatteryIbc), unknown18=\(unknown18), lipoMv=\(lipoMv), unknown22=\(unknown22), unknown24=\(unknown24))"
    }
}
