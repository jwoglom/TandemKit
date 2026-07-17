import Foundation
import LoopKit

/// Maps Tandem HistoryLog events to LoopKit DoseEntry and NewPumpEvent instances.
class HistoryToDoseMapper {
    /// - Parameters:
    ///   - scheduledBasalRate: Loop's scheduled (profile) basal rate at
    ///     a given date. Used to convert a temp basal's pump-stored
    ///     *percent* into an absolute U/hr rate, exactly as the set
    ///     path does (`scheduledRate × percent/100`).
    ///   - roundBasalRate: Rounds a rate to a pump-supported value
    ///     (mirrors the set path).
    ///   - isCommandedBolus: Whether a bolusId corresponds to a bolus
    ///     the controlling app commanded (vs a pump-UI Quick Bolus /
    ///     Control-IQ bolus). Drives `DoseEntry.wasProgrammedByPumpUI`.
    func mapToEvents(
        _ logs: [HistoryLog],
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone,
        scheduledBasalRate: (Date) -> Double,
        roundBasalRate: (Double) -> Double,
        isCommandedBolus: (Int) -> Bool
    ) -> [NewPumpEvent] {
        let sortedLogs = logs.sorted { $0.sequenceNum < $1.sequenceNum }
        recordClockChanges(sortedLogs, reconciler: reconciler)

        var bolusActivations: [Int: BolusActivatedHistoryLog] = [:]
        var tempBasalActivations: [Int: TempRateActivatedHistoryLog] = [:]
        var events: [NewPumpEvent] = []

        for log in sortedLogs {
            switch log {
            case let activation as BolusActivatedHistoryLog:
                bolusActivations[activation.bolusId] = activation
            case let completion as BolusCompletedHistoryLog:
                let activation = bolusActivations.removeValue(forKey: completion.bolusId)
                let dose = buildBolusDose(
                    activation: activation,
                    completion: completion,
                    reconciler: reconciler,
                    insulinType: insulinType,
                    timeZone: timeZone,
                    isCommandedBolus: isCommandedBolus
                )
                events.append(
                    NewPumpEvent(
                        date: dose.endDate,
                        dose: dose,
                        raw: completion.cargo,
                        title: "Bolus",
                        type: .bolus
                    )
                )
            case let activation as TempRateActivatedHistoryLog:
                tempBasalActivations[activation.tempRateId] = activation
            case let completion as TempRateCompletedHistoryLog:
                if let dose = buildTempBasalDose(
                    activation: tempBasalActivations.removeValue(forKey: completion.tempRateId),
                    completion: completion,
                    reconciler: reconciler,
                    insulinType: insulinType,
                    timeZone: timeZone,
                    scheduledBasalRate: scheduledBasalRate,
                    roundBasalRate: roundBasalRate
                ) {
                    events.append(
                        NewPumpEvent(
                            date: dose.startDate,
                            dose: dose,
                            raw: completion.cargo,
                            title: "Temp Basal",
                            type: .tempBasal
                        )
                    )
                }
            case let basalChange as BasalRateChangeHistoryLog:
                let dose = buildBasalDose(
                    basalChange,
                    reconciler: reconciler,
                    insulinType: insulinType,
                    timeZone: timeZone
                )
                events.append(
                    NewPumpEvent(
                        date: dose.startDate,
                        dose: dose,
                        raw: basalChange.cargo,
                        title: "Basal",
                        type: .basal
                    )
                )
            case let alarm as AlarmActivatedHistoryLog:
                events.append(makeAlarmEvent(alarm, reconciler: reconciler, timeZone: timeZone))
            case let alert as AlertActivatedHistoryLog:
                events.append(makeAlarmEvent(alert, reconciler: reconciler, timeZone: timeZone))
            case let suspend as PumpingSuspendedHistoryLog:
                // Source the suspend from the pump's own ledger so it
                // can't be missed.
                let date = reconciler.utcDate(
                    pumpTimeSec: suspend.pumpTimeSec,
                    sequenceNum: suspend.sequenceNum,
                    timeZone: timeZone
                )
                events.append(
                    NewPumpEvent(
                        date: date,
                        dose: DoseEntry(suspendDate: date),
                        raw: suspend.cargo,
                        title: "Suspend",
                        type: .suspend
                    )
                )
            case let resume as PumpingResumedHistoryLog:
                let date = reconciler.utcDate(
                    pumpTimeSec: resume.pumpTimeSec,
                    sequenceNum: resume.sequenceNum,
                    timeZone: timeZone
                )
                events.append(
                    NewPumpEvent(
                        date: date,
                        dose: DoseEntry(resumeDate: date, insulinType: insulinType),
                        raw: resume.cargo,
                        title: "Resume",
                        type: .resume
                    )
                )
            default:
                continue
            }
        }

        for activation in bolusActivations.values {
            let startDate = reconciler.utcDate(
                pumpTimeSec: activation.pumpTimeSec,
                sequenceNum: activation.sequenceNum,
                timeZone: timeZone
            )
            let dose = DoseEntry(
                type: .bolus,
                startDate: startDate,
                value: Self.roundToReportingResolution(Double(activation.bolusSize)),
                unit: .units,
                deliveredUnits: nil,
                description: "Bolus #\(activation.bolusId)",
                syncIdentifier: Self.bolusSyncIdentifier(activation.bolusId),
                insulinType: insulinType,
                wasProgrammedByPumpUI: !isCommandedBolus(activation.bolusId)
            )
            events.append(
                NewPumpEvent(
                    date: dose.startDate,
                    dose: dose,
                    raw: activation.cargo,
                    title: "Bolus",
                    type: .bolus
                )
            )
        }

        for activation in tempBasalActivations.values {
            if let dose = buildTempBasalDose(
                activation: activation,
                completion: nil,
                reconciler: reconciler,
                insulinType: insulinType,
                timeZone: timeZone,
                scheduledBasalRate: scheduledBasalRate,
                roundBasalRate: roundBasalRate
            ) {
                events.append(
                    NewPumpEvent(
                        date: dose.startDate,
                        dose: dose,
                        raw: activation.cargo,
                        title: "Temp Basal",
                        type: .tempBasal
                    )
                )
            }
        }

        return events
    }

    private func recordClockChanges(_ logs: [HistoryLog], reconciler: HistoryTimestampReconciler) {
        for log in logs {
            if let timeChanged = log as? TimeChangedHistoryLog {
                let delta = Int(timeChanged.timeAfter) - Int(timeChanged.timePrior)
                reconciler.recordClockChange(at: timeChanged.sequenceNum, deltaSec: delta)
            } else if let dateChanged = log as? DateChangeHistoryLog {
                let delta = Int(dateChanged.dateAfter) - Int(dateChanged.datePrior)
                reconciler.recordClockChange(at: dateChanged.sequenceNum, deltaSec: delta)
            }
        }
    }

    private func buildBolusDose(
        activation: BolusActivatedHistoryLog?,
        completion: BolusCompletedHistoryLog,
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone,
        isCommandedBolus: (Int) -> Bool
    ) -> DoseEntry {
        let startDate: Date
        if let activation {
            startDate = reconciler.utcDate(
                pumpTimeSec: activation.pumpTimeSec,
                sequenceNum: activation.sequenceNum,
                timeZone: timeZone
            )
        } else {
            startDate = reconciler.utcDate(
                pumpTimeSec: completion.pumpTimeSec,
                sequenceNum: completion.sequenceNum,
                timeZone: timeZone
            )
        }

        let endDate = reconciler.utcDate(
            pumpTimeSec: completion.pumpTimeSec,
            sequenceNum: completion.sequenceNum,
            timeZone: timeZone
        )

        let programmedUnits = Self.roundToReportingResolution(activation.map { Double($0.bolusSize) } ?? Double(completion.insulinRequested))
        let deliveredUnits = Self.roundToReportingResolution(Double(completion.insulinDelivered))

        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: programmedUnits,
            unit: .units,
            deliveredUnits: deliveredUnits,
            description: "Bolus #\(completion.bolusId)",
            syncIdentifier: Self.bolusSyncIdentifier(completion.bolusId),
            insulinType: insulinType,
            wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)
        )
        return dose
    }

    static func bolusSyncIdentifier(_ bolusId: Int) -> String {
        "bolus-\(bolusId)"
    }

    /// Pump bolus id encoded in a mapped bolus dose's `description`. Paired with the
    /// `description: "Bolus #\(bolusId)"` format this mapper produces; `HistoryReconciler` uses it to
    /// match a history bolus to a pending commanded bolus by the pump's unique id.
    static let bolusDescriptionPrefix = "Bolus #"
    static func bolusId(fromDescription description: String?) -> Int? {
        guard let description, description.hasPrefix(bolusDescriptionPrefix) else { return nil }
        return Int(description.dropFirst(bolusDescriptionPrefix.count))
    }

    /// Round a pump-reported insulin amount to the pump's native milliunit reporting resolution,
    /// stripping Float32 representation noise (e.g. `Float(0.9)` = 0.89999997) without distorting
    /// genuine partial deliveries (e.g. a cancelled bolus of 1.041 U). Round-to-**nearest** — NOT
    /// the floor-to-command-grid `roundToSupportedBolusVolume`, which combined with the Float
    /// undershoot could drop a whole increment and understate delivered IOB (the unsafe direction).
    static func roundToReportingResolution(_ units: Double) -> Double {
        (units * 1000).rounded() / 1000
    }

    static func tempBasalSyncIdentifier(_ tempRateId: Int) -> String {
        "tempBasal-\(tempRateId)"
    }

    private func buildTempBasalDose(
        activation: TempRateActivatedHistoryLog?,
        completion: TempRateCompletedHistoryLog?,
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone,
        scheduledBasalRate: (Date) -> Double,
        roundBasalRate: (Double) -> Double
    ) -> DoseEntry? {
        guard let activation else {
            return nil
        }

        let startDate = reconciler.utcDate(
            pumpTimeSec: activation.pumpTimeSec,
            sequenceNum: activation.sequenceNum,
            timeZone: timeZone
        )

        // Convert duration from milliseconds to seconds (TimeInterval)
        let durationSeconds = TimeInterval(activation.durationMilliseconds / 1000)
        let programmedEndDate = startDate.addingTimeInterval(durationSeconds)

        let completionDate: Date
        if let completion {
            completionDate = reconciler.utcDate(
                pumpTimeSec: completion.pumpTimeSec,
                sequenceNum: completion.sequenceNum,
                timeZone: timeZone
            )
        } else {
            completionDate = programmedEndDate
        }

        // Use min() not max() - if temp basal completes early, use the actual completion time
        let endDate = min(programmedEndDate, completionDate)

        // A Tandem temp basal is stored in history as a *percent* of the active profile
        // basal, not an absolute rate. Convert to an absolute U/hr rate exactly as the
        // set path does: round(scheduledBasalRate(at: start) × percent/100). Recording the
        // bare percent/100 here would only be correct when the scheduled basal is 1.0 U/hr.
        let absoluteRate = roundBasalRate(
            scheduledBasalRate(startDate) * Double(activation.percent) / 100.0
        )

        let dose = DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: absoluteRate,
            unit: .unitsPerHour,
            description: "Temp basal #\(activation.tempRateId) at \(activation.percent)%",
            syncIdentifier: Self.tempBasalSyncIdentifier(activation.tempRateId),
            insulinType: insulinType
        )
        return dose
    }

    private func buildBasalDose(
        _ basalChange: BasalRateChangeHistoryLog,
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone
    ) -> DoseEntry {
        let startDate = reconciler.utcDate(
            pumpTimeSec: basalChange.pumpTimeSec,
            sequenceNum: basalChange.sequenceNum,
            timeZone: timeZone
        )

        return DoseEntry(
            type: .basal,
            startDate: startDate,
            value: Double(basalChange.commandBasalRate),
            unit: .unitsPerHour,
            description: "Basal profile \(basalChange.insulinDeliveryProfile)",
            insulinType: insulinType
        )
    }

    private func makeAlarmEvent(
        _ log: HistoryLog,
        reconciler: HistoryTimestampReconciler,
        timeZone: TimeZone
    ) -> NewPumpEvent {
        let date = reconciler.utcDate(
            pumpTimeSec: log.pumpTimeSec,
            sequenceNum: log.sequenceNum,
            timeZone: timeZone
        )

        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: log.cargo,
            title: "Alarm",
            type: .alarm
        )
    }
}
