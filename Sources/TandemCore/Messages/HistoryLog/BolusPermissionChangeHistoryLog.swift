import Foundation

/// Opcode 295 (no Tandem name; provisional): bolus permission granted, then released or revoked. pumpX2#142
public class BolusPermissionChangeHistoryLog: HistoryLog {
    public static let typeId = 295

    public let bolusId: Int
    /// 1 BLE app, 2 Control-IQ, 3 pump UI on the grant record; 0 on the release record (inferred).
    public let unknownU8At12: Int
    /// Byte 12 of the grant record, repeated on the release record; 0 on the grant record (inferred).
    public let unknownU8At13: Int
    public let changeReasonId: Int

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        unknownU8At12 = Int(cargo[12])
        unknownU8At13 = Int(cargo[13])
        changeReasonId = Int(cargo[14])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, unknownU8At12: Int, unknownU8At13: Int, changeReasonId: Int) {
        let payload = BolusPermissionChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            unknownU8At12: unknownU8At12,
            unknownU8At13: unknownU8At13,
            changeReasonId: changeReasonId
        )
        self.bolusId = bolusId
        self.unknownU8At12 = unknownU8At12
        self.unknownU8At13 = unknownU8At13
        self.changeReasonId = changeReasonId
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        unknownU8At12: Int,
        unknownU8At13: Int,
        changeReasonId: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([UInt8(unknownU8At12 & 0xFF), UInt8(unknownU8At13 & 0xFF), UInt8(changeReasonId & 0xFF)])
            )
        )
    }

    public var changeReason: BolusPermissionChangeReasonResponse.ChangeReason? {
        BolusPermissionChangeReasonResponse.ChangeReason(rawValue: changeReasonId)
    }

    public var description: String {
        "BolusPermissionChangeHistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), unknownU8At12=\(unknownU8At12), unknownU8At13=\(unknownU8At13), changeReasonId=\(changeReasonId))"
    }
}
