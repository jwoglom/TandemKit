import Foundation

/// Opcode 293 (no Tandem name; provisional): second of three records copying a BLE InitiateBolusRequest as sent. pumpX2#142
public class InitiateBolusRequestMsg2HistoryLog: HistoryLog {
    public static let typeId = 293

    public let transactionId: Int
    public let bolusId: Int
    /// Milliunits.
    public let correctionVolume: UInt32
    /// Milliunits.
    public let extendedVolume: UInt32
    /// Grams.
    public let bolusCarbs: Int
    /// mg/dL.
    public let bolusBG: Int

    public required init(cargo: Data) {
        transactionId = Int(cargo[10])
        bolusId = Bytes.readShort(cargo, 12)
        correctionVolume = Bytes.readUint32(cargo, 14)
        extendedVolume = Bytes.readUint32(cargo, 18)
        bolusCarbs = Bytes.readShort(cargo, 22)
        bolusBG = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        transactionId: Int,
        bolusId: Int,
        correctionVolume: UInt32,
        extendedVolume: UInt32,
        bolusCarbs: Int,
        bolusBG: Int
    ) {
        let payload = InitiateBolusRequestMsg2HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            transactionId: transactionId,
            bolusId: bolusId,
            correctionVolume: correctionVolume,
            extendedVolume: extendedVolume,
            bolusCarbs: bolusCarbs,
            bolusBG: bolusBG
        )
        self.transactionId = transactionId
        self.bolusId = bolusId
        self.correctionVolume = correctionVolume
        self.extendedVolume = extendedVolume
        self.bolusCarbs = bolusCarbs
        self.bolusBG = bolusBG
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        transactionId: Int,
        bolusId: Int,
        correctionVolume: UInt32,
        extendedVolume: UInt32,
        bolusCarbs: Int,
        bolusBG: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(transactionId & 0xFF), 0]),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toUint32(correctionVolume),
                Bytes.toUint32(extendedVolume),
                Bytes.firstTwoBytesLittleEndian(bolusCarbs),
                Bytes.firstTwoBytesLittleEndian(bolusBG)
            )
        )
    }

    override public var description: String {
        "InitiateBolusRequestMsg2HistoryLog(cargo=\(cargo.hexadecimalString), transactionId=\(transactionId), bolusId=\(bolusId), correctionVolume=\(correctionVolume), extendedVolume=\(extendedVolume), bolusCarbs=\(bolusCarbs), bolusBG=\(bolusBG))"
    }
}
