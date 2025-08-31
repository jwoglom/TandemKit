//
//  TimeChangedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's TimeChangedHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/TimeChangedHistoryLog.java
//
import Foundation

/// History log entry recording a change in the pump's time.
public class TimeChangedHistoryLog: HistoryLog {
    public static let typeId = 13

    public let timePrior: UInt32
    public let timeAfter: UInt32
    public let rawRTC: UInt32

    public required init(cargo: Data) {
        self.timePrior = Bytes.readUint32(cargo, 10)
        self.timeAfter = Bytes.readUint32(cargo, 14)
        self.rawRTC = Bytes.readUint32(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, timePrior: UInt32, timeAfter: UInt32, rawRTC: UInt32) {
        let payload = TimeChangedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, timePrior: timePrior, timeAfter: timeAfter, rawRTC: rawRTC)
        self.timePrior = timePrior
        self.timeAfter = timeAfter
        self.rawRTC = rawRTC
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, timePrior: UInt32, timeAfter: UInt32, rawRTC: UInt32) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(timePrior),
                Bytes.toUint32(timeAfter),
                Bytes.toUint32(rawRTC)
            )
        )
    }
}

