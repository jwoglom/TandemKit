//
//  ControlIQUserModeChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's ControlIQUserModeChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ControlIQUserModeChangeHistoryLog.java
//
import Foundation

/// History log entry indicating a ControlIQ user mode change.
public class ControlIQUserModeChangeHistoryLog: HistoryLog {
    public static let typeId = 229

    public let currentUserMode: Int
    public let previousUserMode: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        currentUserMode = Int(raw[10])
        previousUserMode = Int(raw[11])
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, currentUserMode: Int, previousUserMode: Int) {
        let payload = ControlIQUserModeChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentUserMode: currentUserMode,
            previousUserMode: previousUserMode
        )
        self.currentUserMode = currentUserMode
        self.previousUserMode = previousUserMode
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, currentUserMode: Int, previousUserMode: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(bitPattern: Int8(-27)), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(currentUserMode & 0xFF)]),
                Data([UInt8(previousUserMode & 0xFF)])
            )
        )
    }
}
