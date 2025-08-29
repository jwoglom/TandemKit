//
//  BGHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's BGHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BGHistoryLog.java
//
import Foundation

/// History log entry recording a manual or CGM blood glucose reading.
public class BGHistoryLog: HistoryLog {
    public static let typeId = 16

    public let bg: Int
    public let cgmCalibration: Int
    public let bgSourceId: Int
    public let iob: Float
    public let targetBG: Int
    public let isf: Int
    public let spare: UInt32

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        self.bg = Bytes.readShort(raw, 10)
        self.cgmCalibration = Int(raw[12])
        self.bgSourceId = Int(raw[13])
        self.iob = Bytes.readFloat(raw, 14)
        self.targetBG = Bytes.readShort(raw, 18)
        self.isf = Bytes.readShort(raw, 20)
        self.spare = Bytes.readUint32(raw, 22)
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: Int, cgmCalibration: Int, bgSourceId: Int, iob: Float, targetBG: Int, isf: Int, spare: UInt32) {
        let payload = BGHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bg: bg, cgmCalibration: cgmCalibration, bgSourceId: bgSourceId, iob: iob, targetBG: targetBG, isf: isf, spare: spare)
        self.bg = bg
        self.cgmCalibration = cgmCalibration
        self.bgSourceId = bgSourceId
        self.iob = iob
        self.targetBG = targetBG
        self.isf = isf
        self.spare = spare
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: Int, cgmCalibration: Int, bgSourceId: Int, iob: Float, targetBG: Int, isf: Int, spare: UInt32) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bg),
                Data([UInt8(cgmCalibration & 0xFF)]),
                Data([UInt8(bgSourceId & 0xFF)]),
                Bytes.toFloat(iob),
                Bytes.firstTwoBytesLittleEndian(targetBG),
                Bytes.firstTwoBytesLittleEndian(isf),
                Bytes.toUint32(spare)
            )
        )
    }

    /// Source of the BG entry (CGM or manual).
    public var bgSource: LastBGResponse.BgSource? {
        return LastBGResponse.BgSource(rawValue: bgSourceId)
    }
}

