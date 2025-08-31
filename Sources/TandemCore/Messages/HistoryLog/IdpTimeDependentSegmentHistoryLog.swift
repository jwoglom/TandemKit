//
//  IdpTimeDependentSegmentHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for Personal Profile (IDP) Time Dependent Segment.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/IdpTimeDependentSegmentHistoryLog.java
//
import Foundation

public class IdpTimeDependentSegmentHistoryLog: HistoryLog {
    public static let typeId = 68

    public let idp: Int
    public let status: Int
    public let segmentIndex: Int
    public let modificationType: Int
    public let startTime: Int
    public let basalRate: Int
    public let isf: Int
    public let targetBg: UInt32
    public let carbRatio: Int

    public required init(cargo: Data) {
        self.idp = Int(cargo[10])
        self.status = Int(cargo[11])
        self.segmentIndex = Int(cargo[12])
        self.modificationType = Int(cargo[13])
        self.startTime = Bytes.readShort(cargo, 14)
        self.basalRate = Bytes.readShort(cargo, 16)
        self.isf = Bytes.readShort(cargo, 18)
        self.targetBg = Bytes.readUint32(cargo, 20)
        self.carbRatio = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, status: Int, segmentIndex: Int, modificationType: Int, startTime: Int, basalRate: Int, isf: Int, targetBg: UInt32, carbRatio: Int) {
        let payload = IdpTimeDependentSegmentHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, idp: idp, status: status, segmentIndex: segmentIndex, modificationType: modificationType, startTime: startTime, basalRate: basalRate, isf: isf, targetBg: targetBg, carbRatio: carbRatio)
        self.idp = idp
        self.status = status
        self.segmentIndex = segmentIndex
        self.modificationType = modificationType
        self.startTime = startTime
        self.basalRate = basalRate
        self.isf = isf
        self.targetBg = targetBg
        self.carbRatio = carbRatio
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, status: Int, segmentIndex: Int, modificationType: Int, startTime: Int, basalRate: Int, isf: Int, targetBg: UInt32, carbRatio: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: idp)]),
                Data([UInt8(truncatingIfNeeded: status)]),
                Data([UInt8(truncatingIfNeeded: segmentIndex)]),
                Data([UInt8(truncatingIfNeeded: modificationType)]),
                Bytes.firstTwoBytesLittleEndian(startTime),
                Bytes.firstTwoBytesLittleEndian(basalRate),
                Bytes.firstTwoBytesLittleEndian(isf),
                Bytes.toUint32(targetBg),
                Data([UInt8(truncatingIfNeeded: carbRatio)])
            )
        )
    }
}

