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
    public let selectedIOB: Int
    public let bgSourceType: Int
    public let spare: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        bg = Bytes.readShort(raw, 10)
        cgmCalibration = Int(raw[12])
        bgSourceId = Int(raw[13])
        iob = Bytes.readFloat(raw, 14)
        targetBG = Bytes.readShort(raw, 18)
        isf = Bytes.readShort(raw, 20)
        selectedIOB = Int(raw[22])
        bgSourceType = Int(raw[23])
        spare = Bytes.readShort(raw, 24)
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bg: Int,
        cgmCalibration: Int,
        bgSourceId: Int,
        iob: Float,
        targetBG: Int,
        isf: Int,
        selectedIOB: Int,
        bgSourceType: Int,
        spare: Int
    ) {
        let payload = BGHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bg: bg,
            cgmCalibration: cgmCalibration,
            bgSourceId: bgSourceId,
            iob: iob,
            targetBG: targetBG,
            isf: isf,
            selectedIOB: selectedIOB,
            bgSourceType: bgSourceType,
            spare: spare
        )
        self.bg = bg
        self.cgmCalibration = cgmCalibration
        self.bgSourceId = bgSourceId
        self.iob = iob
        self.targetBG = targetBG
        self.isf = isf
        self.selectedIOB = selectedIOB
        self.bgSourceType = bgSourceType
        self.spare = spare
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bg: Int,
        cgmCalibration: Int,
        bgSourceId: Int,
        iob: Float,
        targetBG: Int,
        isf: Int,
        selectedIOB: Int,
        bgSourceType: Int,
        spare: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bg),
                Data([UInt8(cgmCalibration & 0xFF)]),
                Data([UInt8(bgSourceId & 0xFF)]),
                Bytes.toFloat(iob),
                Bytes.firstTwoBytesLittleEndian(targetBG),
                Bytes.firstTwoBytesLittleEndian(isf),
                Data([UInt8(selectedIOB & 0xFF)]),
                Data([UInt8(bgSourceType & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(spare)
            )
        )
    }

    /// Source of the BG entry (CGM or manual).
    public var bgSource: LastBGResponse.BgSource? {
        LastBGResponse.BgSource(rawValue: bgSourceId)
    }

    public var description: String {
        "BGHistoryLog(cargo=\(cargo.hexadecimalString), bg=\(bg), cgmCalibration=\(cgmCalibration), bgSource=\(String(describing: bgSource)), bgSourceId=\(bgSourceId), iob=\(iob), targetBG=\(targetBG), isf=\(isf), selectedIOB=\(selectedIOB), bgSourceType=\(bgSourceType), spare=\(spare))"
    }
}
