//
//  HistoryLogParser.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Simplified parser converting raw history log bytes into known types.
//

import Foundation

/// Parses raw history log bytes into concrete HistoryLog types.
public enum HistoryLogParser {
    public static func parse(_ raw: Data) -> HistoryLog {
        let typeId = Int(Bytes.readShort(raw, 0) & 0x0FFF)
        switch typeId {
        case AlarmActivatedHistoryLog.typeId:
            return AlarmActivatedHistoryLog(cargo: raw)
        case AlertActivatedHistoryLog.typeId:
            return AlertActivatedHistoryLog(cargo: raw)
        case BasalRateChangeHistoryLog.typeId:
            return BasalRateChangeHistoryLog(cargo: raw)
        case BolusActivatedHistoryLog.typeId:
            return BolusActivatedHistoryLog(cargo: raw)
        case BolusCompletedHistoryLog.typeId:
            return BolusCompletedHistoryLog(cargo: raw)
        case PumpingSuspendedHistoryLog.typeId:
            return PumpingSuspendedHistoryLog(cargo: raw)
        case PumpingResumedHistoryLog.typeId:
            return PumpingResumedHistoryLog(cargo: raw)
        default:
            return UnknownHistoryLog(cargo: raw)
        }
    }
}

