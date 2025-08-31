//
//  NewDayHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's NewDayHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/NewDayHistoryLog.java
//
import Foundation

/// History log entry marking the start of a new day.
public class NewDayHistoryLog: HistoryLog {
    public static let typeId = 90

    public let commandedBasalRate: Float

    public required init(cargo: Data) {
        self.commandedBasalRate = Bytes.readFloat(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, commandedBasalRate: Float) {
        let payload = NewDayHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, commandedBasalRate: commandedBasalRate)
        self.commandedBasalRate = commandedBasalRate
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, commandedBasalRate: Float) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(commandedBasalRate)
            )
        )
    }
}

