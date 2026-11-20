import Foundation

/// Opcode 298 (no Tandem name; provisional): the pump's answer to a BLE InitiateBolusRequest. pumpX2#142
public class InitiateBolusResponseHistoryLog: HistoryLog {
    public static let typeId = 298

    public let bolusId: Int
    /// 0/0 when accepted; one rejection (InitiateBolusResponse status 1, statusTypeId 2) wrote 2/1.
    public let unknownU8At14: Int
    public let unknownU8At15: Int

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        unknownU8At14 = Int(cargo[14])
        unknownU8At15 = Int(cargo[15])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, unknownU8At14: Int, unknownU8At15: Int) {
        let payload = InitiateBolusResponseHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            unknownU8At14: unknownU8At14,
            unknownU8At15: unknownU8At15
        )
        self.bolusId = bolusId
        self.unknownU8At14 = unknownU8At14
        self.unknownU8At15 = unknownU8At15
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, unknownU8At14: Int, unknownU8At15: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([0, 0, UInt8(unknownU8At14 & 0xFF), UInt8(unknownU8At15 & 0xFF)])
            )
        )
    }

    override public var description: String {
        "InitiateBolusResponseHistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), unknownU8At14=\(unknownU8At14), unknownU8At15=\(unknownU8At15))"
    }
}
