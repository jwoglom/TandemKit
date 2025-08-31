//
//  HypoMinimizerResumeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's HypoMinimizerResumeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/HypoMinimizerResumeHistoryLog.java
//
import Foundation

/// History log entry for Hypo Minimizer resume events.
public class HypoMinimizerResumeHistoryLog: HistoryLog {
    public static let typeId = 199

    public let reason: UInt32

    public required init(cargo: Data) {
        self.reason = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, reason: UInt32) {
        let payload = HypoMinimizerResumeHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, reason: reason)
        self.reason = reason
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, reason: UInt32) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(reason)
            )
        )
    }
}

