//
//  LogErasedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's LogErasedHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/LogErasedHistoryLog.java
//
import Foundation

/// History log entry indicating a segment of log entries was erased.
public class LogErasedHistoryLog: HistoryLog {
    public static let typeId = 0

    /// Number of entries erased from the pump history.
    public let numErased: UInt32

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        numErased = Bytes.readUint32(raw, 10)
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, numErased: UInt32) {
        let payload = LogErasedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, numErased: numErased)
        self.numErased = numErased
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, numErased: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([0, 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(numErased)
            )
        )
    }
}
