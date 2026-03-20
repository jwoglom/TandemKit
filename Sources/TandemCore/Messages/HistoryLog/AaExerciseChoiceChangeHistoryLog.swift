//
//  AaExerciseChoiceChangeHistoryLog.swift
//  TandemKit
//
//  Swift representation of PumpX2's AAExerciseChoiceChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/AAExerciseChoiceChangeHistoryLog.java
//
import Foundation

/// History log entry indicating an AA exercise choice change.
public class AaExerciseChoiceChangeHistoryLog: HistoryLog {
    public static let typeId = 319

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = AaExerciseChoiceChangeHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([63, 1]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}
