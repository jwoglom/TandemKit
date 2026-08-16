//
//  AaExerciseTimeChangeHistoryLog.swift
//  TandemKit
//
//  Swift representation of PumpX2's AAExerciseTimeChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/AAExerciseTimeChangeHistoryLog.java
//
import Foundation

/// History log entry indicating an AA exercise time change.
public class AaExerciseTimeChangeHistoryLog: HistoryLog {
    public static let typeId = 318

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = AaExerciseTimeChangeHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}
