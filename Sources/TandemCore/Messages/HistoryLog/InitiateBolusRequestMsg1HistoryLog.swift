import Foundation

/// Opcode 292 (no Tandem name; provisional): first of three records copying a BLE InitiateBolusRequest as sent. pumpX2#142
public class InitiateBolusRequestMsg1HistoryLog: HistoryLog {
    public static let typeId = 292

    /// The request's signature-trailer time as the app sent it; see `BolusPermissionRequestHistoryLog.requestTimestamp`.
    public let requestTimestamp: UInt32
    /// BLE transaction id the InitiateBolusRequest was written with.
    public let transactionId: Int
    public let bolusTypeBitmask: Int
    public let bolusId: Int
    /// Milliunits.
    public let totalVolume: UInt32
    /// Milliunits.
    public let foodVolume: UInt32

    public required init(cargo: Data) {
        requestTimestamp = Bytes.readUint32(cargo, 10)
        transactionId = Int(cargo[14])
        bolusTypeBitmask = Int(cargo[15])
        bolusId = Bytes.readShort(cargo, 16)
        totalVolume = Bytes.readUint32(cargo, 18)
        foodVolume = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        requestTimestamp: UInt32,
        transactionId: Int,
        bolusTypeBitmask: Int,
        bolusId: Int,
        totalVolume: UInt32,
        foodVolume: UInt32
    ) {
        let payload = InitiateBolusRequestMsg1HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            requestTimestamp: requestTimestamp,
            transactionId: transactionId,
            bolusTypeBitmask: bolusTypeBitmask,
            bolusId: bolusId,
            totalVolume: totalVolume,
            foodVolume: foodVolume
        )
        self.requestTimestamp = requestTimestamp
        self.transactionId = transactionId
        self.bolusTypeBitmask = bolusTypeBitmask
        self.bolusId = bolusId
        self.totalVolume = totalVolume
        self.foodVolume = foodVolume
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        requestTimestamp: UInt32,
        transactionId: Int,
        bolusTypeBitmask: Int,
        bolusId: Int,
        totalVolume: UInt32,
        foodVolume: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(requestTimestamp),
                Data([UInt8(transactionId & 0xFF), UInt8(bolusTypeBitmask & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toUint32(totalVolume),
                Bytes.toUint32(foodVolume)
            )
        )
    }

    override public var description: String {
        "InitiateBolusRequestMsg1HistoryLog(cargo=\(cargo.hexadecimalString), requestTimestamp=\(requestTimestamp), transactionId=\(transactionId), bolusTypeBitmask=\(bolusTypeBitmask), bolusId=\(bolusId), totalVolume=\(totalVolume), foodVolume=\(foodVolume))"
    }
}
