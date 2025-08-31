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
        case CGMHistoryLog.typeId:
            return CGMHistoryLog(cargo: raw)
        case CgmCalibrationHistoryLog.typeId:
            return CgmCalibrationHistoryLog(cargo: raw)
        case CgmCalibrationGxHistoryLog.typeId:
            return CgmCalibrationGxHistoryLog(cargo: raw)
        case CgmDataSampleHistoryLog.typeId:
            return CgmDataSampleHistoryLog(cargo: raw)
        case CgmDataGxHistoryLog.typeId:
            return CgmDataGxHistoryLog(cargo: raw)
        case CorrectionDeclinedHistoryLog.typeId:
            return CorrectionDeclinedHistoryLog(cargo: raw)
        case DailyBasalHistoryLog.typeId:
            return DailyBasalHistoryLog(cargo: raw)
        case DataLogCorruptionHistoryLog.typeId:
            return DataLogCorruptionHistoryLog(cargo: raw)
        case DateChangeHistoryLog.typeId:
            return DateChangeHistoryLog(cargo: raw)
        case FactoryResetHistoryLog.typeId:
            return FactoryResetHistoryLog(cargo: raw)
        case HypoMinimizerResumeHistoryLog.typeId:
            return HypoMinimizerResumeHistoryLog(cargo: raw)
        case HypoMinimizerSuspendHistoryLog.typeId:
            return HypoMinimizerSuspendHistoryLog(cargo: raw)
        case NewDayHistoryLog.typeId:
            return NewDayHistoryLog(cargo: raw)
        case TempRateActivatedHistoryLog.typeId:
            return TempRateActivatedHistoryLog(cargo: raw)
        case TempRateCompletedHistoryLog.typeId:
            return TempRateCompletedHistoryLog(cargo: raw)
        case TimeChangedHistoryLog.typeId:
            return TimeChangedHistoryLog(cargo: raw)
        case TubingFilledHistoryLog.typeId:
            return TubingFilledHistoryLog(cargo: raw)
        case PumpingSuspendedHistoryLog.typeId:
            return PumpingSuspendedHistoryLog(cargo: raw)
        case PumpingResumedHistoryLog.typeId:
            return PumpingResumedHistoryLog(cargo: raw)
        case IdpActionHistoryLog.typeId:
            return IdpActionHistoryLog(cargo: raw)
        case IdpActionMsg2HistoryLog.typeId:
            return IdpActionMsg2HistoryLog(cargo: raw)
        case IdpBolusHistoryLog.typeId:
            return IdpBolusHistoryLog(cargo: raw)
        case IdpListHistoryLog.typeId:
            return IdpListHistoryLog(cargo: raw)
        case IdpTimeDependentSegmentHistoryLog.typeId:
            return IdpTimeDependentSegmentHistoryLog(cargo: raw)
        case ParamChangeGlobalSettingsHistoryLog.typeId:
            return ParamChangeGlobalSettingsHistoryLog(cargo: raw)
        case ParamChangePumpSettingsHistoryLog.typeId:
            return ParamChangePumpSettingsHistoryLog(cargo: raw)
        case ParamChangeRemSettingsHistoryLog.typeId:
            return ParamChangeRemSettingsHistoryLog(cargo: raw)
        case ParamChangeReminderHistoryLog.typeId:
            return ParamChangeReminderHistoryLog(cargo: raw)
        default:
            return UnknownHistoryLog(cargo: raw)
        }
    }
}

