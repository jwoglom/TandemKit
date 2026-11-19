import Foundation

/// Opcode 195 (no Tandem name; provisional): insulin the pump adds to IOB as a bolus completes. pumpX2#143
public class BolusIobEntryHistoryLog: HistoryLog {
    public static let typeId = 195

    /// 1 when nothing was delivered (with 0xFF slot and 0xFFFFFFFF duration), else 0.
    public let unknownU8At10: Int
    /// Behaves like the lowest free slot in the pump's bolus IOB table (inferred); 0xFF when nothing was delivered.
    public let unknownU8At11: Int
    /// Milliseconds; the active profile's insulinDuration.
    public let insulinDurationMillis: UInt32
    /// Units; equals BolusCompleted.insulinDelivered.
    public let insulinDelivered: Float
    /// Units after this bolus; equals IobSnapshotPostBolusHistoryLog.mudaliarIob, displayed only when selectedIob is 0.
    public let mudaliarIob: Float

    public required init(cargo: Data) {
        unknownU8At10 = Int(cargo[10])
        unknownU8At11 = Int(cargo[11])
        insulinDurationMillis = Bytes.readUint32(cargo, 14)
        insulinDelivered = Bytes.readFloat(cargo, 18)
        mudaliarIob = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        unknownU8At10: Int,
        unknownU8At11: Int,
        insulinDurationMillis: UInt32,
        insulinDelivered: Float,
        mudaliarIob: Float
    ) {
        let payload = BolusIobEntryHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            unknownU8At10: unknownU8At10,
            unknownU8At11: unknownU8At11,
            insulinDurationMillis: insulinDurationMillis,
            insulinDelivered: insulinDelivered,
            mudaliarIob: mudaliarIob
        )
        self.unknownU8At10 = unknownU8At10
        self.unknownU8At11 = unknownU8At11
        self.insulinDurationMillis = insulinDurationMillis
        self.insulinDelivered = insulinDelivered
        self.mudaliarIob = mudaliarIob
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        unknownU8At10: Int,
        unknownU8At11: Int,
        insulinDurationMillis: UInt32,
        insulinDelivered: Float,
        mudaliarIob: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(unknownU8At10 & 0xFF), UInt8(unknownU8At11 & 0xFF), 0, 0]),
                Bytes.toUint32(insulinDurationMillis),
                Bytes.toFloat(insulinDelivered),
                Bytes.toFloat(mudaliarIob)
            )
        )
    }

    override public var description: String {
        "BolusIobEntryHistoryLog(cargo=\(cargo.hexadecimalString), unknownU8At10=\(unknownU8At10), unknownU8At11=\(unknownU8At11), insulinDurationMillis=\(insulinDurationMillis), insulinDelivered=\(insulinDelivered), mudaliarIob=\(mudaliarIob))"
    }
}
