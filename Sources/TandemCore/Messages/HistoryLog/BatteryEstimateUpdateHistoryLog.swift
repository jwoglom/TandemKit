import Foundation

/// One step of a battery procedure that can change currentBatteryAbc (jwoglom/pumpX2#149).
/// Provisional name; `unknown*` fields are unidentified. `unknown14` is signed; `lipoMv` is millivolts.
public class BatteryEstimateUpdateHistoryLog: HistoryLog {
    public static let typeId = 330

    public let unknown10: Int
    public let unknown11: Int
    public let currentBatteryAbc: Int
    public let unknown13: Int
    public let unknown14: Int
    public let lipoMv: Int
    public let currentBatteryIbc: Int
    public let elapsedMs: UInt32

    public required init(cargo: Data) {
        unknown10 = Int(cargo[10])
        unknown11 = Int(cargo[11])
        currentBatteryAbc = Int(cargo[12])
        unknown13 = Int(cargo[13])
        unknown14 = Int(Int16(bitPattern: UInt16(Bytes.readShort(cargo, 14))))
        lipoMv = Bytes.readShort(cargo, 16)
        currentBatteryIbc = Int(cargo[18])
        elapsedMs = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, unknown10: Int, unknown11: Int, currentBatteryAbc: Int, unknown13: Int, unknown14: Int, lipoMv: Int, currentBatteryIbc: Int, elapsedMs: UInt32) {
        let payload = BatteryEstimateUpdateHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            unknown10: unknown10,
            unknown11: unknown11,
            currentBatteryAbc: currentBatteryAbc,
            unknown13: unknown13,
            unknown14: unknown14,
            lipoMv: lipoMv,
            currentBatteryIbc: currentBatteryIbc,
            elapsedMs: elapsedMs
        )
        self.unknown10 = unknown10
        self.unknown11 = unknown11
        self.currentBatteryAbc = currentBatteryAbc
        self.unknown13 = unknown13
        self.unknown14 = unknown14
        self.lipoMv = lipoMv
        self.currentBatteryIbc = currentBatteryIbc
        self.elapsedMs = elapsedMs
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, unknown10: Int, unknown11: Int, currentBatteryAbc: Int, unknown13: Int, unknown14: Int, lipoMv: Int, currentBatteryIbc: Int, elapsedMs: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(unknown10 & 0xFF)]),
                Data([UInt8(unknown11 & 0xFF)]),
                Data([UInt8(currentBatteryAbc & 0xFF)]),
                Data([UInt8(unknown13 & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(unknown14),
                Bytes.firstTwoBytesLittleEndian(lipoMv),
                Data([UInt8(currentBatteryIbc & 0xFF)]),
                Data(count: 3),
                Bytes.toUint32(elapsedMs)
            )
        )
    }

    override public var description: String {
        "BatteryEstimateUpdateHistoryLog(cargo=\(cargo.hexadecimalString), unknown10=\(unknown10), unknown11=\(unknown11), currentBatteryAbc=\(currentBatteryAbc), unknown13=\(unknown13), unknown14=\(unknown14), lipoMv=\(lipoMv), currentBatteryIbc=\(currentBatteryIbc), elapsedMs=\(elapsedMs))"
    }
}
