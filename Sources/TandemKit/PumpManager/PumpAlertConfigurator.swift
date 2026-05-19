import Foundation

/// Stateless factory for constructing pump alert and reminder configuration requests.
///
/// Each method builds the appropriate `changeBitmask` value so that all supplied
/// parameters are marked as changed in the outgoing message.  The caller is
/// responsible for sending the returned request through `PumpComm` or the
/// transport layer.
public enum PumpAlertConfigurator {
    // MARK: - Auto-Off Alert

    /// Construct a request to enable/disable the auto-off alert and set its duration.
    ///
    /// - Parameters:
    ///   - enabled: Whether the auto-off alert should be enabled.
    ///   - durationMinutes: Duration in minutes before auto-off triggers.
    /// - Returns: A fully populated `SetAutoOffAlertRequest`.
    public static func makeSetAutoOffAlertRequest(
        enabled: Bool,
        durationMinutes: Int
    ) -> SetAutoOffAlertRequest {
        // Bitmask bits: 0 = enableAutoOff, 1 = autoOffDuration
        let bitmask = 0b11
        return SetAutoOffAlertRequest(
            enableAutoOff: enabled,
            autoOffDuration: durationMinutes,
            bitmask: bitmask
        )
    }

    // MARK: - BG Reminder

    /// Construct a request to configure a blood-glucose reminder.
    ///
    /// - Parameters:
    ///   - type: Reminder type (0 = HIGH, 1 = LOW, 2 = AFTER_BOLUS).
    ///     See `SetBgReminderRequest.ReminderType`.
    ///   - enabled: Whether this reminder should be enabled.
    ///   - threshold: BG threshold in mg/dL.
    ///   - minutes: Reminder time in minutes.
    /// - Returns: A fully populated `SetBgReminderRequest`.
    public static func makeSetBgReminderRequest(
        type: Int,
        enabled: Bool,
        threshold: Int,
        minutes: Int
    ) -> SetBgReminderRequest {
        // Bitmask bits: 0 = enabled, 1 = threshold, 2 = minutes
        let bitmask = 0b111
        return SetBgReminderRequest(
            reminderType: type,
            enabledBGReminder: enabled,
            reminderThreshold: threshold,
            reminderMinutes: UInt32(minutes),
            bitmask: bitmask
        )
    }

    // MARK: - Low Insulin Alert

    /// Construct a request to set the low-insulin alert threshold.
    ///
    /// - Parameter threshold: Low insulin threshold in units.
    /// - Returns: A fully populated `SetLowInsulinAlertRequest`.
    public static func makeSetLowInsulinAlertRequest(
        threshold: Int
    ) -> SetLowInsulinAlertRequest {
        SetLowInsulinAlertRequest(insulinThreshold: threshold)
    }

    // MARK: - Site Change Reminder

    /// Construct a request to configure the site-change reminder.
    ///
    /// - Parameters:
    ///   - enabled: Whether the reminder should be enabled.
    ///   - dayCount: Number of days between site changes.
    ///   - timeOfDayMinutes: Time of day for the reminder, in minutes since midnight.
    /// - Returns: A fully populated `SetSiteChangeReminderRequest`.
    public static func makeSetSiteChangeReminderRequest(
        enabled: Bool,
        dayCount: Int,
        timeOfDayMinutes: Int
    ) -> SetSiteChangeReminderRequest {
        // Bitmask bits: 0 = enable, 1 = dayCount, 2 = timeOfDay
        let bitmask = 0b111
        return SetSiteChangeReminderRequest(
            enable: enabled,
            dayCount: dayCount,
            timeOfDayMinutes: UInt32(timeOfDayMinutes),
            bitmask: bitmask
        )
    }

    // MARK: - Missed Meal Bolus Reminder

    /// Construct a request to configure a missed-meal-bolus reminder slot.
    ///
    /// - Parameters:
    ///   - index: Reminder slot index.
    ///   - enabled: Whether this reminder slot should be enabled.
    ///   - startTime: Start time in minutes since midnight.
    ///   - endTime: End time in minutes since midnight.
    ///   - selectedDays: Days-of-week bitmask (bit 0 = Mon, 1 = Tue, ..., 6 = Sun).
    /// - Returns: A fully populated `SetMissedMealBolusReminderRequest`.
    public static func makeSetMissedMealBolusReminderRequest(
        index: Int,
        enabled: Bool,
        startTime: Int,
        endTime: Int,
        selectedDays: Int
    ) -> SetMissedMealBolusReminderRequest {
        // Bitmask bits: 0 = enabled, 1 = startTime, 2 = endTime, 3 = selectedDays
        let bitmask = 0b1111
        return SetMissedMealBolusReminderRequest(
            reminderIndex: index,
            enabledReminder: enabled,
            startTime: startTime,
            endTime: endTime,
            selectedDays: selectedDays,
            bitmask: bitmask
        )
    }

    // MARK: - CGM High/Low Alert

    /// Construct a request to configure a CGM high or low glucose alert.
    ///
    /// - Parameters:
    ///   - threshold: Alert threshold in mg/dL.
    ///   - repeatDurationMinutes: Minutes before the alert repeats.
    ///   - alertType: `.high` or `.low`.
    ///   - enabled: Whether this alert should be enabled.
    /// - Returns: A fully populated `CgmHighLowAlertRequest`.
    public static func makeSetCgmHighLowAlertRequest(
        threshold: Int,
        repeatDurationMinutes: Int,
        alertType: CgmHighLowAlertRequest.AlertType,
        enabled: Bool
    ) -> CgmHighLowAlertRequest {
        // Bitmask bits: 0 = enabled, 1 = threshold, 2 = repeatDuration
        let bitmask = 0b111
        return CgmHighLowAlertRequest(
            alertType: alertType.rawValue,
            threshold: threshold,
            repeatDurationMinutes: repeatDurationMinutes,
            enableAlert: enabled,
            bitmask: bitmask
        )
    }

    // MARK: - CGM Out-of-Range Alert

    /// Construct a request to configure the CGM out-of-range alert.
    ///
    /// - Parameters:
    ///   - enabled: Whether the alert should be enabled.
    ///   - alertDelay: Delay in minutes before the alert fires.
    /// - Returns: A fully populated `CgmOutOfRangeAlertRequest`.
    public static func makeSetCgmOutOfRangeAlertRequest(
        enabled: Bool,
        alertDelay: Int
    ) -> CgmOutOfRangeAlertRequest {
        // Bitmask bits: 0 = enabled, 1 = delayBeforeAlert
        let bitmask = 0b11
        return CgmOutOfRangeAlertRequest(
            enable: enabled,
            alertDelay: alertDelay,
            bitmask: bitmask
        )
    }

    // MARK: - CGM Rise/Fall Alert

    /// Construct a request to configure a CGM rise or fall rate alert.
    ///
    /// - Parameters:
    ///   - alertType: `.rise` or `.fall`.
    ///   - enabled: Whether this alert should be enabled.
    ///   - mgPerDl: Rate threshold in mg/dL per minute.
    /// - Returns: A fully populated `CgmRiseFallAlertRequest`.
    public static func makeSetCgmRiseFallAlertRequest(
        alertType: CgmRiseFallAlertRequest.AlertType,
        enabled: Bool,
        mgPerDl: Int
    ) -> CgmRiseFallAlertRequest {
        // Bitmask bits: 0 = enabled, 1 = minValue
        let bitmask = 0b11
        return CgmRiseFallAlertRequest(
            alertType: alertType.rawValue,
            enable: enabled,
            mgPerDl: mgPerDl,
            bitmask: bitmask
        )
    }
}
