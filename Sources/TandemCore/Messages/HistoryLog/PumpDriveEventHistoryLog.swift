import Foundation

/// Opcode 277 (no Tandem name; provisional): Mobi drive-mechanism record at bolus start/end, fills and retraction. pumpX2#144
public class PumpDriveEventHistoryLog: HistoryLog {
    public static let typeId = 277

    /// Drive position: rises ~1,080 counts per unit delivered (54 per 0.05 U step), falls during cartridge retraction.
    public let driveCounter: UInt32
    /// Signed; usually equal to unknownI16At16. <=60 on delivery steps, ~300 on fills, ~-2000 on retraction.
    public let unknownI16At14: Int
    public let unknownI16At16: Int
    public let unknownU8At18: Int
    public let unknownU8At19: Int
    public let unknownU8At20: Int
    public let unknownU8At21: Int
    /// 0xFFFF on most delivery steps.
    public let unknownU16At22: Int
    public let unknownU16At24: Int

    public required init(cargo: Data) {
        driveCounter = Bytes.readUint32(cargo, 10)
        unknownI16At14 = Int(Int16(truncatingIfNeeded: Bytes.readShort(cargo, 14)))
        unknownI16At16 = Int(Int16(truncatingIfNeeded: Bytes.readShort(cargo, 16)))
        unknownU8At18 = Int(cargo[18])
        unknownU8At19 = Int(cargo[19])
        unknownU8At20 = Int(cargo[20])
        unknownU8At21 = Int(cargo[21])
        unknownU16At22 = Bytes.readShort(cargo, 22)
        unknownU16At24 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        driveCounter: UInt32,
        unknownI16At14: Int,
        unknownI16At16: Int,
        unknownU8At18: Int,
        unknownU8At19: Int,
        unknownU8At20: Int,
        unknownU8At21: Int,
        unknownU16At22: Int,
        unknownU16At24: Int
    ) {
        let payload = PumpDriveEventHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            driveCounter: driveCounter,
            unknownI16At14: unknownI16At14,
            unknownI16At16: unknownI16At16,
            unknownU8At18: unknownU8At18,
            unknownU8At19: unknownU8At19,
            unknownU8At20: unknownU8At20,
            unknownU8At21: unknownU8At21,
            unknownU16At22: unknownU16At22,
            unknownU16At24: unknownU16At24
        )
        self.driveCounter = driveCounter
        self.unknownI16At14 = unknownI16At14
        self.unknownI16At16 = unknownI16At16
        self.unknownU8At18 = unknownU8At18
        self.unknownU8At19 = unknownU8At19
        self.unknownU8At20 = unknownU8At20
        self.unknownU8At21 = unknownU8At21
        self.unknownU16At22 = unknownU16At22
        self.unknownU16At24 = unknownU16At24
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        driveCounter: UInt32,
        unknownI16At14: Int,
        unknownI16At16: Int,
        unknownU8At18: Int,
        unknownU8At19: Int,
        unknownU8At20: Int,
        unknownU8At21: Int,
        unknownU16At22: Int,
        unknownU16At24: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(driveCounter),
                Bytes.firstTwoBytesLittleEndian(unknownI16At14),
                Bytes.firstTwoBytesLittleEndian(unknownI16At16),
                Data([UInt8(unknownU8At18 & 0xFF), UInt8(unknownU8At19 & 0xFF), UInt8(unknownU8At20 & 0xFF), UInt8(unknownU8At21 & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(unknownU16At22),
                Bytes.firstTwoBytesLittleEndian(unknownU16At24)
            )
        )
    }

    override public var description: String {
        "PumpDriveEventHistoryLog(cargo=\(cargo.hexadecimalString), driveCounter=\(driveCounter), unknownI16At14=\(unknownI16At14), unknownI16At16=\(unknownI16At16), unknownU8At18=\(unknownU8At18), unknownU8At19=\(unknownU8At19), unknownU8At20=\(unknownU8At20), unknownU8At21=\(unknownU8At21), unknownU16At22=\(unknownU16At22), unknownU16At24=\(unknownU16At24))"
    }
}
