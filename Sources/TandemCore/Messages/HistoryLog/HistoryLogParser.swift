import Foundation

/// Parses raw history log bytes into concrete HistoryLog types.
public enum HistoryLogParser {
    public static func parse(_ raw: Data) -> HistoryLog {
        let typeId = Int(Bytes.readShort(raw, 0) & 0x0FFF)
        switch typeId {
        case AlarmActivatedHistoryLog.typeId:
            return AlarmActivatedHistoryLog(cargo: raw)
        case MalfunctionAckHistoryLog.typeId:
            return MalfunctionAckHistoryLog(cargo: raw)
        case AlarmAckHistoryLog.typeId:
            return AlarmAckHistoryLog(cargo: raw)
        case AlarmClearedHistoryLog.typeId:
            return AlarmClearedHistoryLog(cargo: raw)
        case AlertActivatedHistoryLog.typeId:
            return AlertActivatedHistoryLog(cargo: raw)
        case ReminderActivatedHistoryLog.typeId:
            return ReminderActivatedHistoryLog(cargo: raw)
        case AlertAckHistoryLog.typeId:
            return AlertAckHistoryLog(cargo: raw)
        case AlertClearedHistoryLog.typeId:
            return AlertClearedHistoryLog(cargo: raw)
        case ReminderDismissedHistoryLog.typeId:
            return ReminderDismissedHistoryLog(cargo: raw)
        case ReminderSnoozedHistoryLog.typeId:
            return ReminderSnoozedHistoryLog(cargo: raw)
        case CartridgeRemovedHistoryLog.typeId:
            return CartridgeRemovedHistoryLog(cargo: raw)
        case CartridgeInsertedHistoryLog.typeId:
            return CartridgeInsertedHistoryLog(cargo: raw)
        case ArmInitHistoryLog.typeId:
            return ArmInitHistoryLog(cargo: raw)
        case BasalRateChangeHistoryLog.typeId:
            return BasalRateChangeHistoryLog(cargo: raw)
        case BolusActivatedHistoryLog.typeId:
            return BolusActivatedHistoryLog(cargo: raw)
        case BolusCompletedHistoryLog.typeId:
            return BolusCompletedHistoryLog(cargo: raw)
        case CgmAlertAckDexHistoryLog.typeId:
            return CgmAlertAckDexHistoryLog(cargo: raw)
        case CgmAlertActivatedDexHistoryLog.typeId:
            return CgmAlertActivatedDexHistoryLog(cargo: raw)
        case CgmAlertActivatedFsl2HistoryLog.typeId:
            return CgmAlertActivatedFsl2HistoryLog(cargo: raw)
        case CgmAlertActivatedHistoryLog.typeId:
            return CgmAlertActivatedHistoryLog(cargo: raw)
        case CgmAlertClearedDexHistoryLog.typeId:
            return CgmAlertClearedDexHistoryLog(cargo: raw)
        case CgmAlertClearedFsl2HistoryLog.typeId:
            return CgmAlertClearedFsl2HistoryLog(cargo: raw)
        case CgmAlertClearedHistoryLog.typeId:
            return CgmAlertClearedHistoryLog(cargo: raw)
        case ConfirmCartridgeFilledHistoryLog.typeId:
            return ConfirmCartridgeFilledHistoryLog(cargo: raw)
        case FillEstimateFinalHistoryLog.typeId:
            return FillEstimateFinalHistoryLog(cargo: raw)
        case CgmCalibrationHistoryLog.typeId:
            return CgmCalibrationHistoryLog(cargo: raw)
        case BasalIqSettingsChangeHistoryLog.typeId:
            return BasalIqSettingsChangeHistoryLog(cargo: raw)
        case CgmTransmitterIdHistoryLog.typeId:
            return CgmTransmitterIdHistoryLog(cargo: raw)
        case CgmAnnuSettingsHistoryLog.typeId:
            return CgmAnnuSettingsHistoryLog(cargo: raw)
        case CgmStopSessionMsg1HistoryLog.typeId:
            return CgmStopSessionMsg1HistoryLog(cargo: raw)
        case CgmStopSessionMsg2HistoryLog.typeId:
            return CgmStopSessionMsg2HistoryLog(cargo: raw)
        case CgmHgaSettingsHistoryLog.typeId:
            return CgmHgaSettingsHistoryLog(cargo: raw)
        case CgmLgaSettingsHistoryLog.typeId:
            return CgmLgaSettingsHistoryLog(cargo: raw)
        case CgmRraSettingsHistoryLog.typeId:
            return CgmRraSettingsHistoryLog(cargo: raw)
        case CgmFraSettingsHistoryLog.typeId:
            return CgmFraSettingsHistoryLog(cargo: raw)
        case CgmOorSettingsHistoryLog.typeId:
            return CgmOorSettingsHistoryLog(cargo: raw)
        case CgmAlertAckHistoryLog.typeId:
            return CgmAlertAckHistoryLog(cargo: raw)
        case CgmUnexpectedGeAlertHistoryLog.typeId:
            return CgmUnexpectedGeAlertHistoryLog(cargo: raw)
        case CgmCalibrationGxHistoryLog.typeId:
            return CgmCalibrationGxHistoryLog(cargo: raw)
        case CgmDataFsl2HistoryLog.typeId:
            return CgmDataFsl2HistoryLog(cargo: raw)
        case CgmDataFsl3HistoryLog.typeId:
            return CgmDataFsl3HistoryLog(cargo: raw)
        case CgmDataSampleHistoryLog.typeId:
            return CgmDataSampleHistoryLog(cargo: raw)
        case CgmDataGxHistoryLog.typeId:
            return CgmDataGxHistoryLog(cargo: raw)
        case CgmJoinSessionHistoryLog.typeId:
            return CgmJoinSessionHistoryLog(cargo: raw)
        case CgmJoinSessionFsl2HistoryLog.typeId:
            return CgmJoinSessionFsl2HistoryLog(cargo: raw)
        case CgmJoinSessionFsl3HistoryLog.typeId:
            return CgmJoinSessionFsl3HistoryLog(cargo: raw)
        case CgmJoinSessionG7HistoryLog.typeId:
            return CgmJoinSessionG7HistoryLog(cargo: raw)
        case CgmStartSessionHistoryLog.typeId:
            return CgmStartSessionHistoryLog(cargo: raw)
        case CgmStartSessionFsl2HistoryLog.typeId:
            return CgmStartSessionFsl2HistoryLog(cargo: raw)
        case CgmStopSessionHistoryLog.typeId:
            return CgmStopSessionHistoryLog(cargo: raw)
        case CgmInactiveGxHistoryLog.typeId:
            return CgmInactiveGxHistoryLog(cargo: raw)
        case CgmTransmitterIdGxHistoryLog.typeId:
            return CgmTransmitterIdGxHistoryLog(cargo: raw)
        case CgmStartSessionReqGxHistoryLog.typeId:
            return CgmStartSessionReqGxHistoryLog(cargo: raw)
        case CgmStopSessionReqGxHistoryLog.typeId:
            return CgmStopSessionReqGxHistoryLog(cargo: raw)
        case CgmTransmitterVersionGxHistoryLog.typeId:
            return CgmTransmitterVersionGxHistoryLog(cargo: raw)
        case CgmStopSessionFsl2HistoryLog.typeId:
            return CgmStopSessionFsl2HistoryLog(cargo: raw)
        case CgmStopSessionFsl3HistoryLog.typeId:
            return CgmStopSessionFsl3HistoryLog(cargo: raw)
        case CgmStopSessionG7HistoryLog.typeId:
            return CgmStopSessionG7HistoryLog(cargo: raw)
        case CorrectionDeclinedHistoryLog.typeId:
            return CorrectionDeclinedHistoryLog(cargo: raw)
        case DailyStatusHistoryLog.typeId:
            return DailyStatusHistoryLog(cargo: raw)
        case DailyBasalHistoryLog.typeId:
            return DailyBasalHistoryLog(cargo: raw)
        case DataLogCorruptionHistoryLog.typeId:
            return DataLogCorruptionHistoryLog(cargo: raw)
        case DateChangeHistoryLog.typeId:
            return DateChangeHistoryLog(cargo: raw)
        case DexcomG6CGMHistoryLog.typeId:
            return DexcomG6CGMHistoryLog(cargo: raw)
        case DexcomG7CGMHistoryLog.typeId:
            return DexcomG7CGMHistoryLog(cargo: raw)
        case FactoryResetHistoryLog.typeId:
            return FactoryResetHistoryLog(cargo: raw)
        case HypoMinimizerResumeHistoryLog.typeId:
            return HypoMinimizerResumeHistoryLog(cargo: raw)
        case HypoMinimizerSuspendHistoryLog.typeId:
            return HypoMinimizerSuspendHistoryLog(cargo: raw)
        case NewDayHistoryLog.typeId:
            return NewDayHistoryLog(cargo: raw)
        case MalfunctionHistoryLog.typeId:
            return MalfunctionHistoryLog(cargo: raw)
        case TempRateActivatedHistoryLog.typeId:
            return TempRateActivatedHistoryLog(cargo: raw)
        case TempRateCompletedHistoryLog.typeId:
            return TempRateCompletedHistoryLog(cargo: raw)
        case TimeChangedHistoryLog.typeId:
            return TimeChangedHistoryLog(cargo: raw)
        case TubingFilledHistoryLog.typeId:
            return TubingFilledHistoryLog(cargo: raw)
        case PlgsPeriodicHistoryLog.typeId:
            return PlgsPeriodicHistoryLog(cargo: raw)
        case PumpingSuspendedHistoryLog.typeId:
            return PumpingSuspendedHistoryLog(cargo: raw)
        case PumpingResumedHistoryLog.typeId:
            return PumpingResumedHistoryLog(cargo: raw)
        case ShelfModeHistoryLog.typeId:
            return ShelfModeHistoryLog(cargo: raw)
        case UpdateStatusHistoryLog.typeId:
            return UpdateStatusHistoryLog(cargo: raw)
        case VersionInfoHistoryLog.typeId:
            return VersionInfoHistoryLog(cargo: raw)
        case VersionsAHistoryLog.typeId:
            return VersionsAHistoryLog(cargo: raw)
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
        case AaSleepScheduleChangeHistoryLog.typeId:
            return AaSleepScheduleChangeHistoryLog(cargo: raw)
        case AaDeliveryStatusChangeHistoryLog.typeId:
            return AaDeliveryStatusChangeHistoryLog(cargo: raw)
        case AaEnableSettingChangeHistoryLog.typeId:
            return AaEnableSettingChangeHistoryLog(cargo: raw)
        case AaTdiSettingChangeHistoryLog.typeId:
            return AaTdiSettingChangeHistoryLog(cargo: raw)
        case AaWeightSettingChangeHistoryLog.typeId:
            return AaWeightSettingChangeHistoryLog(cargo: raw)
        case CgmSessionTypeChangeHistoryLog.typeId:
            return CgmSessionTypeChangeHistoryLog(cargo: raw)
        case WumpOcclusionDebugHistoryLog.typeId:
            return WumpOcclusionDebugHistoryLog(cargo: raw)
        case SnoozeActivatedHistoryLog.typeId:
            return SnoozeActivatedHistoryLog(cargo: raw)
        case AaAutoBolusRejectedHistoryLog.typeId:
            return AaAutoBolusRejectedHistoryLog(cargo: raw)
        case TipscReqPrimeCannulaHistoryLog.typeId:
            return TipscReqPrimeCannulaHistoryLog(cargo: raw)
        case WumpCartridgeFilledHistoryLog.typeId:
            return WumpCartridgeFilledHistoryLog(cargo: raw)
        case WumpCartridgeRemovedHistoryLog.typeId:
            return WumpCartridgeRemovedHistoryLog(cargo: raw)
        case AaTdiEstChangeHistoryLog.typeId:
            return AaTdiEstChangeHistoryLog(cargo: raw)
        case AaExerciseTimeChangeHistoryLog.typeId:
            return AaExerciseTimeChangeHistoryLog(cargo: raw)
        case AaExerciseChoiceChangeHistoryLog.typeId:
            return AaExerciseChoiceChangeHistoryLog(cargo: raw)
        case PrimeInprocessHistoryLog.typeId:
            return PrimeInprocessHistoryLog(cargo: raw)
        case CgmRejoinSessionHistoryLog.typeId:
            return CgmRejoinSessionHistoryLog(cargo: raw)
        case CgmSensorTypeChangeHistoryLog.typeId:
            return CgmSensorTypeChangeHistoryLog(cargo: raw)
        case CgmStartSensorReqG7HistoryLog.typeId:
            return CgmStartSensorReqG7HistoryLog(cargo: raw)
        case CgmPairingCodeG7HistoryLog.typeId:
            return CgmPairingCodeG7HistoryLog(cargo: raw)
        case TipsErrorHistoryLog.typeId:
            return TipsErrorHistoryLog(cargo: raw)
        case CgmCalibrationG7HistoryLog.typeId:
            return CgmCalibrationG7HistoryLog(cargo: raw)
        case CgmBleCalibrationEvtG7HistoryLog.typeId:
            return CgmBleCalibrationEvtG7HistoryLog(cargo: raw)
        case CgmInactiveG7HistoryLog.typeId:
            return CgmInactiveG7HistoryLog(cargo: raw)
        case CgmStopSessionReqG7HistoryLog.typeId:
            return CgmStopSessionReqG7HistoryLog(cargo: raw)
        case LogErasedHistoryLog.typeId:
            return LogErasedHistoryLog(cargo: raw)
        case BGHistoryLog.typeId:
            return BGHistoryLog(cargo: raw)
        case BolexCompletedHistoryLog.typeId:
            return BolexCompletedHistoryLog(cargo: raw)
        case CartridgeFilledHistoryLog.typeId:
            return CartridgeFilledHistoryLog(cargo: raw)
        case UsbConnectedHistoryLog.typeId:
            return UsbConnectedHistoryLog(cargo: raw)
        case UsbDisconnectedHistoryLog.typeId:
            return UsbDisconnectedHistoryLog(cargo: raw)
        case CarbEnteredHistoryLog.typeId:
            return CarbEnteredHistoryLog(cargo: raw)
        case BolexActivatedHistoryLog.typeId:
            return BolexActivatedHistoryLog(cargo: raw)
        case CannulaFilledHistoryLog.typeId:
            return CannulaFilledHistoryLog(cargo: raw)
        case BolusRequestedMsg1HistoryLog.typeId:
            return BolusRequestedMsg1HistoryLog(cargo: raw)
        case BolusRequestedMsg2HistoryLog.typeId:
            return BolusRequestedMsg2HistoryLog(cargo: raw)
        case BolusRequestedMsg3HistoryLog.typeId:
            return BolusRequestedMsg3HistoryLog(cargo: raw)
        case InitiateBolusRequestMsg1HistoryLog.typeId:
            return InitiateBolusRequestMsg1HistoryLog(cargo: raw)
        case InitiateBolusRequestMsg2HistoryLog.typeId:
            return InitiateBolusRequestMsg2HistoryLog(cargo: raw)
        case BolusPermissionChangeHistoryLog.typeId:
            return BolusPermissionChangeHistoryLog(cargo: raw)
        case BolusPermissionResponseHistoryLog.typeId:
            return BolusPermissionResponseHistoryLog(cargo: raw)
        case InitiateBolusResponseHistoryLog.typeId:
            return InitiateBolusResponseHistoryLog(cargo: raw)
        case BolusPermissionRequestHistoryLog.typeId:
            return BolusPermissionRequestHistoryLog(cargo: raw)
        case InitiateBolusRequestMsg3HistoryLog.typeId:
            return InitiateBolusRequestMsg3HistoryLog(cargo: raw)
        case UsbEnumeratedHistoryLog.typeId:
            return UsbEnumeratedHistoryLog(cargo: raw)
        case ControlIQUserModeChangeHistoryLog.typeId:
            return ControlIQUserModeChangeHistoryLog(cargo: raw)
        case ControlIQPcmChangeHistoryLog.typeId:
            return ControlIQPcmChangeHistoryLog(cargo: raw)
        case BasalDeliveryHistoryLog.typeId:
            return BasalDeliveryHistoryLog(cargo: raw)
        case BolusDeliveryHistoryLog.typeId:
            return BolusDeliveryHistoryLog(cargo: raw)
        default:
            return UnknownHistoryLog(cargo: raw)
        }
    }
}
