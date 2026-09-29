import Foundation
import LoopKit

/// Maps Tandem history log records to the LoopKit `NewPumpEvent`s that report them to the host
/// app.
///
/// Pure: emitting and reconciling against live reports are the caller's job. Every `raw` is a
/// `HistoryLogSyncIdentifier`, stable however often the window is re-fetched.
final class HistoryToDoseMapper {
    /// Maps one fetched window of history logs to pump events, in ascending date order.
    ///
    /// - Parameters:
    ///   - reconciler: Carries clock-change corrections. The window's own clock-change records
    ///     are recorded into it before any timestamp is converted, and it accumulates across
    ///     calls so corrections seen in one window apply to earlier windows fetched later.
    ///   - pumpSerial: Serial of the pump the logs came from; part of every identity because
    ///     `bolusId`/`tempRateId` are small counters that repeat across pumps. Requiring the
    ///     validated wrapper means no mapping can happen until the serial is actually known.
    ///   - scheduledBasalRate: The scheduled (profile) basal rate at a given date. Used to
    ///     convert a temp basal's pump-stored *percent* into an absolute U/hr rate, exactly as
    ///     the set path does (`scheduledRate × percent/100`).
    ///   - roundBasalRate: Rounds a rate to a pump-supported value (mirrors the set path).
    ///   - isCommandedBolus: Whether a `bolusId` corresponds to a bolus the controlling app
    ///     commanded (vs a pump-UI Quick Bolus / Control-IQ bolus). Drives
    ///     `DoseEntry.wasProgrammedByPumpUI`.
    func mapToEvents(
        _ logs: [HistoryLog],
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        scheduledBasalRate: (Date) -> Double,
        roundBasalRate: (Double) -> Double,
        isCommandedBolus: (Int) -> Bool
    ) -> [NewPumpEvent] {
        let sortedLogs = logs.sorted { $0.sequenceNum < $1.sequenceNum }
        reconciler.recordClockChanges(in: sortedLogs)

        let controlIqTriggeredBolusIds = Self.controlIqTriggeredBolusIds(in: sortedLogs)
        var bolusActivations: [Int: BolusActivatedHistoryLog] = [:]
        var tempBasalActivations: [Int: TempRateActivatedHistoryLog] = [:]
        var events: [NewPumpEvent] = []

        for log in sortedLogs {
            switch log {
            case let activation as BolusActivatedHistoryLog:
                bolusActivations[activation.bolusId] = activation
            case let completion as BolusCompletedHistoryLog:
                events.append(completedBolusEvent(
                    activation: bolusActivations.removeValue(forKey: completion.bolusId),
                    completion: completion,
                    reconciler: reconciler,
                    pumpSerial: pumpSerial,
                    insulinType: insulinType,
                    isControlIqTriggered: controlIqTriggeredBolusIds.contains(completion.bolusId),
                    isCommandedBolus: isCommandedBolus
                ))
            case let activation as TempRateActivatedHistoryLog:
                tempBasalActivations[activation.tempRateId] = activation
            case let completion as TempRateCompletedHistoryLog:
                // A completion whose activation is outside the window can't be mapped: the
                // percent, duration and start time all live on the activation record.
                if let activation = tempBasalActivations.removeValue(forKey: completion.tempRateId) {
                    events.append(tempBasalEvent(
                        activation: activation,
                        completion: completion,
                        reconciler: reconciler,
                        pumpSerial: pumpSerial,
                        insulinType: insulinType,
                        scheduledBasalRate: scheduledBasalRate,
                        roundBasalRate: roundBasalRate
                    ))
                }
            case let basalChange as BasalRateChangeHistoryLog:
                events.append(basalChangeEvent(
                    basalChange,
                    reconciler: reconciler,
                    pumpSerial: pumpSerial,
                    insulinType: insulinType
                ))
            case let alarm as AlarmActivatedHistoryLog:
                events.append(alarmEvent(alarm, reconciler: reconciler, pumpSerial: pumpSerial))
            case let alert as AlertActivatedHistoryLog:
                events.append(alarmEvent(alert, reconciler: reconciler, pumpSerial: pumpSerial))
            case let suspend as PumpingSuspendedHistoryLog:
                // Source the suspend from the pump's own ledger so it can't be missed even when
                // it happened while the app wasn't connected.
                let date = reconciler.utcDate(pumpTimeSec: suspend.pumpTimeSec, sequenceNum: suspend.sequenceNum)
                let raw = HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: suspend.sequenceNum)
                // Built with the full initializer rather than DoseEntry(suspendDate:) so the
                // syncIdentifier can be stamped to match `raw`.
                let dose = DoseEntry(
                    type: .suspend,
                    startDate: date,
                    value: 0,
                    unit: .units,
                    syncIdentifier: raw.hexadecimalString
                )
                events.append(NewPumpEvent(date: date, dose: dose, raw: raw, title: "Suspend", type: .suspend))
            case let resume as PumpingResumedHistoryLog:
                let date = reconciler.utcDate(pumpTimeSec: resume.pumpTimeSec, sequenceNum: resume.sequenceNum)
                let raw = HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: resume.sequenceNum)
                let dose = DoseEntry(
                    type: .resume,
                    startDate: date,
                    value: 0,
                    unit: .units,
                    syncIdentifier: raw.hexadecimalString,
                    insulinType: insulinType
                )
                events.append(NewPumpEvent(date: date, dose: dose, raw: raw, title: "Resume", type: .resume))
            default:
                continue
            }
        }

        // Activations with no completion in the window are in flight (or their completion sits
        // in a chunk not fetched yet). They are reported as MUTABLE doses under the same
        // pump-assigned identity their completion will carry, so the finalized dose replaces
        // them in place. Reporting them immutable would be wrong the other way: a finalized row
        // is never revised, so the completion's actual delivered amount would be dropped.
        for activation in bolusActivations.values {
            events.append(inFlightBolusEvent(
                activation,
                reconciler: reconciler,
                pumpSerial: pumpSerial,
                insulinType: insulinType,
                isControlIqTriggered: controlIqTriggeredBolusIds.contains(activation.bolusId),
                isCommandedBolus: isCommandedBolus
            ))
        }

        for activation in tempBasalActivations.values {
            events.append(tempBasalEvent(
                activation: activation,
                completion: nil,
                reconciler: reconciler,
                pumpSerial: pumpSerial,
                insulinType: insulinType,
                scheduledBasalRate: scheduledBasalRate,
                roundBasalRate: roundBasalRate
            ))
        }

        // Dictionary iteration above is unordered, and the host app applies events in the order
        // given; sort so the result is deterministic and ascending.
        return events.sorted { $0.date < $1.date }
    }

    /// Round a pump-reported insulin amount to the pump's native milliunit reporting resolution,
    /// stripping Float32 representation noise (e.g. `Float(0.9)` = 0.89999997) without
    /// distorting genuine partial deliveries (e.g. a cancelled bolus of 1.041 U). Round-to-
    /// **nearest** — NOT the floor-to-command-grid `roundToSupportedBolusVolume`, which combined
    /// with the Float undershoot could drop a whole increment and understate delivered IOB (the
    /// unsafe direction).
    static func roundToReportingResolution(_ units: Double) -> Double {
        (units * 1000).rounded() / 1000
    }

    /// Set explicitly because Trio reads a nil `automatic` as an SMB.
    private static func controlIqTriggeredBolusIds(in logs: [HistoryLog]) -> Set<Int> {
        var ids = Set<Int>()
        for log in logs {
            switch log {
            case let delivery as BolusDeliveryHistoryLog where delivery.bolusSourceEnum == .controlIQAutoBolus:
                ids.insert(delivery.bolusID)
            case let request as BolusRequestedMsg2HistoryLog
                where request.bolusOption == .automatic || request.bolusOption == .eatingSoonAutomatic:
                ids.insert(request.bolusId)
            default:
                continue
            }
        }
        return ids
    }

    // MARK: - Event builders

    private func completedBolusEvent(
        activation: BolusActivatedHistoryLog?,
        completion: BolusCompletedHistoryLog,
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isControlIqTriggered: Bool,
        isCommandedBolus: (Int) -> Bool
    ) -> NewPumpEvent {
        let endDate = reconciler.utcDate(pumpTimeSec: completion.pumpTimeSec, sequenceNum: completion.sequenceNum)
        let startDate: Date
        if let activation {
            startDate = reconciler.utcDate(pumpTimeSec: activation.pumpTimeSec, sequenceNum: activation.sequenceNum)
        } else {
            startDate = endDate
        }

        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: completion.bolusId)
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: Self.roundToReportingResolution(activation.map { Double($0.bolusSize) } ?? Double(completion.insulinRequested)),
            unit: .units,
            deliveredUnits: Self.roundToReportingResolution(Double(completion.insulinDelivered)),
            description: "Bolus #\(completion.bolusId)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            automatic: isControlIqTriggered,
            wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)
        )
        // Trio times a bolus's insulin action from the event date.
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Bolus", type: .bolus)
    }

    private func inFlightBolusEvent(
        _ activation: BolusActivatedHistoryLog,
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isControlIqTriggered: Bool,
        isCommandedBolus: (Int) -> Bool
    ) -> NewPumpEvent {
        let startDate = reconciler.utcDate(pumpTimeSec: activation.pumpTimeSec, sequenceNum: activation.sequenceNum)
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: activation.bolusId)
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            value: Self.roundToReportingResolution(Double(activation.bolusSize)),
            unit: .units,
            description: "Bolus #\(activation.bolusId)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            automatic: isControlIqTriggered,
            isMutable: true,
            wasProgrammedByPumpUI: !isCommandedBolus(activation.bolusId)
        )
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Bolus", type: .bolus)
    }

    private func tempBasalEvent(
        activation: TempRateActivatedHistoryLog,
        completion: TempRateCompletedHistoryLog?,
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        scheduledBasalRate: (Date) -> Double,
        roundBasalRate: (Double) -> Double
    ) -> NewPumpEvent {
        let startDate = reconciler.utcDate(pumpTimeSec: activation.pumpTimeSec, sequenceNum: activation.sequenceNum)
        let programmedEndDate = startDate.addingTimeInterval(TimeInterval(activation.durationMilliseconds / 1000))

        // An early cancel writes the completion before the programmed end; a temp rate that ran
        // its course can write it slightly after. The delivery never extends past the programmed
        // end, so take the earlier of the two.
        let endDate: Date
        if let completion {
            let completionDate = reconciler.utcDate(pumpTimeSec: completion.pumpTimeSec, sequenceNum: completion.sequenceNum)
            endDate = min(programmedEndDate, completionDate)
        } else {
            endDate = programmedEndDate
        }

        // A Tandem temp basal is stored in history as a *percent* of the active profile basal,
        // not an absolute rate. Convert to an absolute U/hr rate exactly as the set path does:
        // round(scheduledBasalRate(at: start) × percent/100). Recording the bare percent/100
        // would only be correct when the scheduled basal is 1.0 U/hr.
        let absoluteRate = roundBasalRate(scheduledBasalRate(startDate) * Double(activation.percent) / 100.0)

        let raw = HistoryLogSyncIdentifier.tempRate(pumpSerial: pumpSerial, tempRateId: activation.tempRateId)
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: absoluteRate,
            unit: .unitsPerHour,
            description: "Temp basal #\(activation.tempRateId) at \(activation.percent)%",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            isMutable: completion == nil
        )
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Temp Basal", type: .tempBasal)
    }

    private func basalChangeEvent(
        _ basalChange: BasalRateChangeHistoryLog,
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?
    ) -> NewPumpEvent {
        let startDate = reconciler.utcDate(pumpTimeSec: basalChange.pumpTimeSec, sequenceNum: basalChange.sequenceNum)
        let raw = HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: basalChange.sequenceNum)
        let dose = DoseEntry(
            type: .basal,
            startDate: startDate,
            value: Double(basalChange.commandBasalRate),
            unit: .unitsPerHour,
            description: "Basal profile \(basalChange.insulinDeliveryProfile)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType
        )
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Basal", type: .basal)
    }

    private func alarmEvent(
        _ log: HistoryLog,
        reconciler: HistoryTimestampReconciler,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial
    ) -> NewPumpEvent {
        NewPumpEvent(
            date: reconciler.utcDate(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum),
            dose: nil,
            raw: HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: log.sequenceNum),
            title: "Alarm",
            type: .alarm
        )
    }
}
