//
//  ControlIQPcmChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's ControlIQPcmChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ControlIQPcmChangeHistoryLog.java
//
import Foundation

/// History log entry indicating a ControlIQ Pump Control Mode (PCM) change.
public class ControlIQPcmChangeHistoryLog: HistoryLog {
    public static let typeId = 230

    public let currentPcm: Int
    public let previousPcm: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        currentPcm = Int(raw[10])
        previousPcm = Int(raw[11])
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, currentPcm: Int, previousPcm: Int) {
        let payload = ControlIQPcmChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentPcm: currentPcm,
            previousPcm: previousPcm
        )
        self.currentPcm = currentPcm
        self.previousPcm = previousPcm
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, currentPcm: Int, previousPcm: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(bitPattern: Int8(-26)), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(currentPcm & 0xFF)]),
                Data([UInt8(previousPcm & 0xFF)])
            )
        )
    }
}
