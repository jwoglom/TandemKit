//
//  BolusRequestedMsg1HistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  First part of a multi-message bolus request log.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusRequestedMsg1HistoryLog.java
//
import Foundation

public class BolusRequestedMsg1HistoryLog: HistoryLog {
    public static let typeId = 64

    public let bolusId: Int
    public let bolusTypeId: Int
    public let correctionBolusIncluded: Bool
    public let carbAmount: Int
    public let bg: Int
    public let iob: Float
    /// Thousandths of a gram per unit; 0 unless `bolusType` is `.CARB`. See `carbRatioGramsPerUnit`.
    public let carbRatio: UInt32

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        bolusTypeId = Int(cargo[12])
        correctionBolusIncluded = cargo[13] != 0
        carbAmount = Bytes.readShort(cargo, 14)
        bg = Bytes.readShort(cargo, 16)
        iob = Bytes.readFloat(cargo, 18)
        carbRatio = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        bolusTypeId: Int,
        correctionBolusIncluded: Bool,
        carbAmount: Int,
        bg: Int,
        iob: Float,
        carbRatio: UInt32
    ) {
        let payload = BolusRequestedMsg1HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            bolusTypeId: bolusTypeId,
            correctionBolusIncluded: correctionBolusIncluded,
            carbAmount: carbAmount,
            bg: bg,
            iob: iob,
            carbRatio: carbRatio
        )
        self.bolusId = bolusId
        self.bolusTypeId = bolusTypeId
        self.correctionBolusIncluded = correctionBolusIncluded
        self.carbAmount = carbAmount
        self.bg = bg
        self.iob = iob
        self.carbRatio = carbRatio
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        bolusTypeId: Int,
        correctionBolusIncluded: Bool,
        carbAmount: Int,
        bg: Int,
        iob: Float,
        carbRatio: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([UInt8(bolusTypeId & 0xFF)]),
                Data([correctionBolusIncluded ? 1 : 0]),
                Bytes.firstTwoBytesLittleEndian(carbAmount),
                Bytes.firstTwoBytesLittleEndian(bg),
                Bytes.toFloat(iob),
                Bytes.toUint32(carbRatio)
            )
        )
    }

    public var carbRatioGramsPerUnit: Double { Double(carbRatio) / 1000.0 }

    /// How the bolus was requested, or `nil` if the raw value is not recognized.
    ///
    /// Treated as a scalar enum over `bolusTypeId` (mirroring pumpX2's
    /// `BolusRequestedMsg1HistoryLog.BolusType`), *not* a bitmask -- deliberately distinct from
    /// `BolusDeliveryHistoryLog.BolusType`, which decodes a different field as a bitmask of the
    /// components making up a bolus.
    public var bolusType: BolusType? {
        BolusType(rawValue: bolusTypeId)
    }

    /// Mirrors pumpX2's `BolusRequestedMsg1HistoryLog.BolusType`. Value names ported from
    /// tconnectsync and not independently verified against pump firmware; see the Java class doc.
    public enum BolusType: Int {
        case INSULIN = 0
        case CARB = 1
        case AUTOMATIC_CORRECTION = 2
        case REMOTE = 3
    }

    override public var description: String {
        "BolusRequestedMsg1HistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), bolusTypeId=\(bolusTypeId), correctionBolusIncluded=\(correctionBolusIncluded), carbAmount=\(carbAmount), bg=\(bg), iob=\(iob), carbRatio=\(carbRatio))"
    }
}
