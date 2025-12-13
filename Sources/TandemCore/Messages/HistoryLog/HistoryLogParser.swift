import Foundation

/// Parses raw history log bytes into concrete HistoryLog types.
public enum HistoryLogParser {
    public static func parse(_ raw: Data) -> HistoryLog {
        let typeId = Int(Bytes.readShort(raw, 0) & 0x0FFF)
        switch typeId {
        case MalfunctionHistoryLog.typeId:
            return MalfunctionHistoryLog(cargo: raw)
        case AlarmActivatedHistoryLog.typeId:
            return AlarmActivatedHistoryLog(cargo: raw)
        case AlarmClearedHistoryLog.typeId:
            return AlarmClearedHistoryLog(cargo: raw)
        case AlertActivatedHistoryLog.typeId:
            return AlertActivatedHistoryLog(cargo: raw)
        case AlertClearedHistoryLog.typeId:
            return AlertClearedHistoryLog(cargo: raw)
        case BasalRateChangeHistoryLog.typeId:
            return BasalRateChangeHistoryLog(cargo: raw)
        case BolusActivatedHistoryLog.typeId:
            return BolusActivatedHistoryLog(cargo: raw)
        case BolusCompletedHistoryLog.typeId:
            return BolusCompletedHistoryLog(cargo: raw)
        case ArmInitHistoryLog.typeId:
            return ArmInitHistoryLog(cargo: raw)
        case DexcomG6CGMHistoryLog.typeId:
            return DexcomG6CGMHistoryLog(cargo: raw)
        case CgmCalibrationHistoryLog.typeId:
            return CgmCalibrationHistoryLog(cargo: raw)
        case CgmCalibrationGxHistoryLog.typeId:
            return CgmCalibrationGxHistoryLog(cargo: raw)
        case CgmDataSampleHistoryLog.typeId:
            return CgmDataSampleHistoryLog(cargo: raw)
        case CgmDataGxHistoryLog.typeId:
            return CgmDataGxHistoryLog(cargo: raw)
        case DexcomG7CGMHistoryLog.typeId:
            return DexcomG7CGMHistoryLog(cargo: raw)
        case CgmDataFsl2HistoryLog.typeId:
            return CgmDataFsl2HistoryLog(cargo: raw)
        case CgmDataFsl3HistoryLog.typeId:
            return CgmDataFsl3HistoryLog(cargo: raw)
        case CorrectionDeclinedHistoryLog.typeId:
            return CorrectionDeclinedHistoryLog(cargo: raw)
        case DailyBasalHistoryLog.typeId:
            return DailyBasalHistoryLog(cargo: raw)
        case UpdateStatusHistoryLog.typeId:
            return UpdateStatusHistoryLog(cargo: raw)
        case DataLogCorruptionHistoryLog.typeId:
            return DataLogCorruptionHistoryLog(cargo: raw)
        case DateChangeHistoryLog.typeId:
            return DateChangeHistoryLog(cargo: raw)
        case FactoryResetHistoryLog.typeId:
            return FactoryResetHistoryLog(cargo: raw)
        case VersionInfoHistoryLog.typeId:
            return VersionInfoHistoryLog(cargo: raw)
        case VersionsAHistoryLog.typeId:
            return VersionsAHistoryLog(cargo: raw)
        case PlgsPeriodicHistoryLog.typeId:
            return PlgsPeriodicHistoryLog(cargo: raw)
        case ShelfModeHistoryLog.typeId:
            return ShelfModeHistoryLog(cargo: raw)
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
        case CgmAlertActivatedHistoryLog.typeId:
            return CgmAlertActivatedHistoryLog(cargo: raw)
        case CgmAlertClearedHistoryLog.typeId:
            return CgmAlertClearedHistoryLog(cargo: raw)
        case CgmAlertActivatedDexHistoryLog.typeId:
            return CgmAlertActivatedDexHistoryLog(cargo: raw)
        case CgmAlertClearedDexHistoryLog.typeId:
            return CgmAlertClearedDexHistoryLog(cargo: raw)
        case CgmAlertAckDexHistoryLog.typeId:
            return CgmAlertAckDexHistoryLog(cargo: raw)
        case CgmAlertActivatedFsl2HistoryLog.typeId:
            return CgmAlertActivatedFsl2HistoryLog(cargo: raw)
        case CgmAlertClearedFsl2HistoryLog.typeId:
            return CgmAlertClearedFsl2HistoryLog(cargo: raw)
        case CgmJoinSessionHistoryLog.typeId:
            return CgmJoinSessionHistoryLog(cargo: raw)
        case CgmJoinSessionG7HistoryLog.typeId:
            return CgmJoinSessionG7HistoryLog(cargo: raw)
        case CgmJoinSessionFsl2HistoryLog.typeId:
            return CgmJoinSessionFsl2HistoryLog(cargo: raw)
        case CgmJoinSessionFsl3HistoryLog.typeId:
            return CgmJoinSessionFsl3HistoryLog(cargo: raw)
        case CgmStartSessionHistoryLog.typeId:
            return CgmStartSessionHistoryLog(cargo: raw)
        case CgmStartSessionFsl2HistoryLog.typeId:
            return CgmStartSessionFsl2HistoryLog(cargo: raw)
        case CgmStopSessionHistoryLog.typeId:
            return CgmStopSessionHistoryLog(cargo: raw)
        case CgmStopSessionFsl2HistoryLog.typeId:
            return CgmStopSessionFsl2HistoryLog(cargo: raw)
        case CgmStopSessionG7HistoryLog.typeId:
            return CgmStopSessionG7HistoryLog(cargo: raw)
        case CgmStopSessionFsl3HistoryLog.typeId:
            return CgmStopSessionFsl3HistoryLog(cargo: raw)
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
