import Foundation
import LoopKit

/// A dose ending before it starts crashed Trio's Apple Health upload at every launch until its row was
/// deleted, so none leaves the driver, whichever path misdated it; each caught is logged as a bug.
enum HostDoseDates {
    /// Past this a start is no second-later nudge (`resumedTempBasal`, a Bolex start) but a wrong date.
    static let startAheadTolerance: TimeInterval = .minutes(1)

    static func startsAhead(_ dose: DoseEntry, of now: Date) -> Bool {
        dose.startDate > now.addingTimeInterval(startAheadTolerance)
    }

    /// `event` with an end the host can store, and what was wrong with it; nil when nothing was.
    static func repaired(_ event: NewPumpEvent) -> (event: NewPumpEvent, problem: String)? {
        guard let dose = event.dose else { return nil }

        var problems: [String] = []
        var start = dose.startDate
        var end = dose.endDate
        if end < start {
            problems.append("ends at \(end), before it starts at \(start)")
            // Zero length, which both hosts count as nothing rather than a guessed duration.
            if dose.type == .tempBasal {
                start = end
            } else {
                end = start
            }
        }
        let deliveredUnits = dose.deliveredUnits.map { units -> Double in
            guard dose.type == .tempBasal, end != dose.endDate || start != dose.startDate else { return max(0, units) }
            return TandemPumpCapabilities.roundToReportingResolution(dose.unitsPerHour * end.timeIntervalSince(start) / .hours(1))
        }
        if let units = dose.deliveredUnits, units < 0 {
            problems.append("delivered \(units) U")
        }
        guard !problems.isEmpty else { return nil }

        let isTemp = dose.type == .tempBasal
        let repaired = DoseEntry(
            type: dose.type,
            startDate: start,
            endDate: end,
            value: isTemp ? dose.unitsPerHour : dose.programmedUnits,
            unit: isTemp ? .unitsPerHour : .units,
            decisionId: dose.decisionId,
            deliveredUnits: deliveredUnits,
            description: dose.description,
            syncIdentifier: dose.syncIdentifier,
            scheduledBasalRate: dose.scheduledBasalRate,
            insulinType: dose.insulinType,
            automatic: dose.automatic,
            manuallyEntered: dose.manuallyEntered,
            isMutable: dose.isMutable,
            wasProgrammedByPumpUI: dose.wasProgrammedByPumpUI
        )
        let date = event.date == dose.startDate ? start : event.date
        return (
            NewPumpEvent(date: date, dose: repaired, raw: event.raw, title: event.title, type: event.type, alarmType: event.alarmType),
            problems.joined(separator: "; ")
        )
    }
}

extension TandemPumpManager {
    /// Left out of a replacing batch, a dose the host holds as mutable is deleted, which is what a
    /// dose with no knowable date should be.
    func withDatesTheHostCanStore(_ events: [NewPumpEvent]) -> [NewPumpEvent] {
        events.compactMap { event in
            if refusesForItsDate(event, now: now) {
                return nil
            }
            guard let (repaired, problem) = HostDoseDates.repaired(event) else { return event }
            logger.error("Misdated \(event.dose?.type.rawValue ?? "event") \(event.raw.hexadecimalString) \(problem); sent as \(repaired.dose?.startDate ?? repaired.date) to \(repaired.dose?.endDate ?? repaired.date)")
            return repaired
        }
    }

    /// Whether `event` starts ahead of the phone, or did when it was first refused.
    func refusesForItsDate(_ event: NewPumpEvent, now: Date) -> Bool {
        guard let dose = event.dose,
              HostDoseDates.startsAhead(dose, of: now) || state.futureDatedDoseRefusals.contains(event.raw, now: now)
        else {
            return false
        }
        let description = "\(dose.type.rawValue) \(event.raw.hexadecimalString) of \(dose.value) \(dose.unit.rawValue) starting \(dose.startDate), as of the phone's \(now)"
        if state.futureDatedDoseRefusals.record(raw: event.raw, startDate: dose.startDate, at: now) {
            logger.error("Refused \(description); not sent to the app (\(state.futureDatedDoseRefusals.count) refused so far)")
        } else {
            logger.debug("Refused again: \(description)")
        }
        return true
    }
}
