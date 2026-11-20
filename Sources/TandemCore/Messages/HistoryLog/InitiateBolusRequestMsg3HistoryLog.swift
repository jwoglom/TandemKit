import Foundation

/// Opcode 343 (no Tandem name; provisional): third of three records copying a BLE InitiateBolusRequest as sent. pumpX2#142
public class InitiateBolusRequestMsg3HistoryLog: HistoryLog {
    public static let typeId = 343

    public let transactionId: Int
    public let bolusId: Int
    /// Milliunits, the app's figure as sent (TandemKit sends 0), not the pump's IOB.
    public let bolusIOB: UInt32
    public let extendedSeconds: UInt32
    public let extended3: UInt32

    public required init(cargo: Data) {
        transactionId = Int(cargo[10])
        bolusId = Bytes.readShort(cargo, 12)
        bolusIOB = Bytes.readUint32(cargo, 14)
        extendedSeconds = Bytes.readUint32(cargo, 18)
        extended3 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        transactionId: Int,
        bolusId: Int,
        bolusIOB: UInt32,
        extendedSeconds: UInt32,
        extended3: UInt32
    ) {
        let payload = InitiateBolusRequestMsg3HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            transactionId: transactionId,
            bolusId: bolusId,
            bolusIOB: bolusIOB,
            extendedSeconds: extendedSeconds,
            extended3: extended3
        )
        self.transactionId = transactionId
        self.bolusId = bolusId
        self.bolusIOB = bolusIOB
        self.extendedSeconds = extendedSeconds
        self.extended3 = extended3
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        transactionId: Int,
        bolusId: Int,
        bolusIOB: UInt32,
        extendedSeconds: UInt32,
        extended3: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(transactionId & 0xFF), 0]),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toUint32(bolusIOB),
                Bytes.toUint32(extendedSeconds),
                Bytes.toUint32(extended3)
            )
        )
    }

    override public var description: String {
        "InitiateBolusRequestMsg3HistoryLog(cargo=\(cargo.hexadecimalString), transactionId=\(transactionId), bolusId=\(bolusId), bolusIOB=\(bolusIOB), extendedSeconds=\(extendedSeconds), extended3=\(extended3))"
    }
}
