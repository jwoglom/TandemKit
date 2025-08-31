//
//  CorrectionDeclinedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's CorrectionDeclinedHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CorrectionDeclinedHistoryLog.java
//
import Foundation

/// History log entry for a declined correction bolus.
public class CorrectionDeclinedHistoryLog: HistoryLog {
    public static let typeId = 93

    public let bg: Int
    public let bolusId: Int
    public let iob: Float
    public let targetBg: Int
    public let isf: Int

    public required init(cargo: Data) {
        self.bg = Bytes.readShort(cargo, 10)
        self.bolusId = Bytes.readShort(cargo, 12)
        self.iob = Bytes.readFloat(cargo, 14)
        self.targetBg = Bytes.readShort(cargo, 18)
        self.isf = Bytes.readShort(cargo, 20)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: Int, bolusId: Int, iob: Float, targetBg: Int, isf: Int) {
        let payload = CorrectionDeclinedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bg: bg, bolusId: bolusId, iob: iob, targetBg: targetBg, isf: isf)
        self.bg = bg
        self.bolusId = bolusId
        self.iob = iob
        self.targetBg = targetBg
        self.isf = isf
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: Int, bolusId: Int, iob: Float, targetBg: Int, isf: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bg),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toFloat(iob),
                Bytes.firstTwoBytesLittleEndian(targetBg),
                Bytes.firstTwoBytesLittleEndian(isf)
            )
        )
    }
}

