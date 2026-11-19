import Foundation

/// Opcode 194 (no Tandem name; provisional): one per completed bolus, X2 and Mobi. The relations are exact; their purpose is unknown. pumpX2#144
public class BolusDeliverySummaryHistoryLog: HistoryLog {
    public static let typeId = 194

    /// Boluses, this one included, within roughly the last 60 minutes (edge not reproduced exactly).
    public let unknownU8At10: Int
    /// +1 per bolus, wrapping 29 -> 0.
    public let unknownU8At11: Int
    /// Ten times BolusCompleted.insulinDelivered.
    public let unknownFloatAt14: Float
    /// Always equal to unknownFloatAt14 so far.
    public let unknownFloatAt18: Float
    /// Sum of unknownFloatAt14 over the boluses counted in unknownU8At10.
    public let unknownFloatAt22: Float

    public required init(cargo: Data) {
        unknownU8At10 = Int(cargo[10])
        unknownU8At11 = Int(cargo[11])
        unknownFloatAt14 = Bytes.readFloat(cargo, 14)
        unknownFloatAt18 = Bytes.readFloat(cargo, 18)
        unknownFloatAt22 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        unknownU8At10: Int,
        unknownU8At11: Int,
        unknownFloatAt14: Float,
        unknownFloatAt18: Float,
        unknownFloatAt22: Float
    ) {
        let payload = BolusDeliverySummaryHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            unknownU8At10: unknownU8At10,
            unknownU8At11: unknownU8At11,
            unknownFloatAt14: unknownFloatAt14,
            unknownFloatAt18: unknownFloatAt18,
            unknownFloatAt22: unknownFloatAt22
        )
        self.unknownU8At10 = unknownU8At10
        self.unknownU8At11 = unknownU8At11
        self.unknownFloatAt14 = unknownFloatAt14
        self.unknownFloatAt18 = unknownFloatAt18
        self.unknownFloatAt22 = unknownFloatAt22
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        unknownU8At10: Int,
        unknownU8At11: Int,
        unknownFloatAt14: Float,
        unknownFloatAt18: Float,
        unknownFloatAt22: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(unknownU8At10 & 0xFF), UInt8(unknownU8At11 & 0xFF), 0, 0]),
                Bytes.toFloat(unknownFloatAt14),
                Bytes.toFloat(unknownFloatAt18),
                Bytes.toFloat(unknownFloatAt22)
            )
        )
    }

    override public var description: String {
        "BolusDeliverySummaryHistoryLog(cargo=\(cargo.hexadecimalString), unknownU8At10=\(unknownU8At10), unknownU8At11=\(unknownU8At11), unknownFloatAt14=\(unknownFloatAt14), unknownFloatAt18=\(unknownFloatAt18), unknownFloatAt22=\(unknownFloatAt22))"
    }
}
