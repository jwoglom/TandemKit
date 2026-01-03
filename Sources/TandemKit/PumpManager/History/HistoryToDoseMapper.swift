import Foundation
import LoopKit
import TandemCore

/// Maps Tandem HistoryLog events to LoopKit DoseEntry and NewPumpEvent instances.
class HistoryToDoseMapper {
    func mapToEvents(
        _ logs: [HistoryLog],
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone
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
                    timeZone: timeZone
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
                    timeZone: timeZone
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
                value: Double(activation.bolusSize),
                unit: .units,
                deliveredUnits: nil,
                description: "Bolus #\(activation.bolusId)",
                insulinType: insulinType,
                isMutable: true
            )
            events.append(
                NewPumpEvent(
                    date: dose.startDate,
                    dose: dose,
                    isMutable: true,
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
                timeZone: timeZone
            ) {
                events.append(
                    NewPumpEvent(
                        date: dose.startDate,
                        dose: dose,
                        isMutable: true,
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
        timeZone: TimeZone
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

        let programmedUnits = activation.map { Double($0.bolusSize) } ?? Double(completion.insulinRequested)
        let deliveredUnits = Double(completion.insulinDelivered)

        return DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: programmedUnits,
            unit: .units,
            deliveredUnits: deliveredUnits,
            description: "Bolus #\(completion.bolusId)",
            insulinType: insulinType
        )
    }

    private func buildTempBasalDose(
        activation: TempRateActivatedHistoryLog?,
        completion: TempRateCompletedHistoryLog?,
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone
    ) -> DoseEntry? {
        guard let activation else {
            return nil
        }

        let startDate = reconciler.utcDate(
            pumpTimeSec: activation.pumpTimeSec,
            sequenceNum: activation.sequenceNum,
            timeZone: timeZone
        )

        let durationSeconds = TimeInterval(activation.duration * 60)
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

        let endDate = max(programmedEndDate, completionDate)

        return DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: Double(activation.percent) / 100.0,
            unit: .unitsPerHour,
            description: "Temp basal #\(activation.tempRateId) at \(activation.percent)%",
            insulinType: insulinType,
            isMutable: completion == nil
        )
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
