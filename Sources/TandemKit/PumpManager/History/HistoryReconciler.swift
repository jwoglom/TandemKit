import Foundation
import LoopKit

/// Matches locally-tracked pending doses with history-derived pump events.
class HistoryReconciler {
    private let matchWindow: TimeInterval = 5 * 60
    private let bolusTolerance: Double = 0.05
    private let basalTolerance: Double = 0.01
    private let uncertainAge = TimeInterval.days(1)

    func reconcile(
        pendingDoses: [PendingDose],
        historyEvents: [NewPumpEvent],
        now: Date = Date()
    ) -> (
        reconciledEvents: [NewPumpEvent],
        stillPending: [PendingDose],
        uncertainPending: [PendingDose]
    ) {
        var remainingPending = pendingDoses
        var reconciledEvents: [NewPumpEvent] = []

        for event in historyEvents {
            guard let dose = event.dose else {
                reconciledEvents.append(event)
                continue
            }

            if let matchIndex = remainingPending.firstIndex(where: { matches($0, to: dose) }) {
                let pending = remainingPending[matchIndex]
                let syncId = pending.syncIdentifier
                remainingPending.remove(at: matchIndex)
                // Finalize the pending (optimistic) dose in place: keep its identity fields — crucially
                // `startDate` — and overlay only the pump-authoritative delivered amount from history.
                //
                // Why NOT the history event's startDate: the syncIdentifier is derived from the
                // optimistic units + startDate, and LoopKit keys/reconciles doses by syncIdentifier. The
                // pump's actual bolus-start time lags the command time by BLE/queue latency (~20 s), so using it
                // makes the finalized dose's startDate contradict its own syncId. LoopKit then fails to
                // convert the optimistic *mutable* dose to immutable in place; it stays mutable and gets
                // swept by the next bolus's `replacePendingEvents: true`, so the recovered bolus vanishes
                // from IOB entirely. This mirrors the normal connected finalize, which reuses the
                // optimistic UnfinalizedDose.startDate.
                let updatedDose = DoseEntry(
                    type: pending.dose.type,
                    startDate: pending.dose.startDate,
                    endDate: dose.endDate,
                    value: pending.dose.programmedUnits,
                    unit: pending.dose.unit,
                    deliveredUnits: dose.deliveredUnits,
                    description: dose.description ?? pending.dose.description,
                    syncIdentifier: syncId,
                    scheduledBasalRate: pending.dose.scheduledBasalRate,
                    insulinType: pending.dose.insulinType ?? dose.insulinType,
                    automatic: pending.dose.automatic ?? dose.automatic,
                    isMutable: false
                )
                // CRITICAL: NewPumpEvent.init overwrites dose.syncIdentifier with raw.hexadecimalString,
                // so the identity must come from `raw`. Use the bytes that hex back to the pending
                // syncIdentifier; fall back to the history raw only if that syncId isn't valid hex.
                let updatedEvent = NewPumpEvent(
                    date: event.date,
                    dose: updatedDose,
                    raw: Data(hexadecimalString: syncId) ?? event.raw,
                    title: event.title,
                    type: event.type
                )
                reconciledEvents.append(updatedEvent)
            } else {
                reconciledEvents.append(event)
            }
        }

        let uncertain = remainingPending.filter { now.timeIntervalSince($0.requestedAt) >= uncertainAge }

        return (reconciledEvents, remainingPending, uncertain)
    }

    private func matches(_ pending: PendingDose, to eventDose: DoseEntry) -> Bool {
        // Strongest anchor: the pump-assigned bolusId (unique + pump-authoritative). When BOTH sides
        // carry it, it is decisive — equal ids match, different ids do NOT, and we do not fall through
        // to the time+amount heuristic (which could otherwise mis-pair two same-amount boluses close in
        // time). Only when a bolusId is missing on either side (non-bolus dose, or an entry persisted
        // before the id was tracked) do we use the fallback below.
        if let pendingBolusId = pending.bolusId,
           let eventBolusId = HistoryToDoseMapper.bolusId(fromDescription: eventDose.description)
        {
            return pendingBolusId == eventBolusId
        }

        if let pendingSyncIdentifier = pending.dose.syncIdentifier,
           let eventSyncIdentifier = eventDose.syncIdentifier,
           pendingSyncIdentifier == eventSyncIdentifier
        {
            return true
        }

        guard pending.dose.type == eventDose.type else {
            return false
        }

        let timeDrift = abs(pending.dose.startDate.timeIntervalSince(eventDose.startDate))
        guard timeDrift <= matchWindow else {
            return false
        }

        switch pending.dose.type {
        case .bolus:
            return closeEnough(
                expected: pending.dose.deliveredUnits ?? pending.dose.programmedUnits,
                actual: eventDose.deliveredUnits ?? eventDose.programmedUnits,
                tolerance: bolusTolerance
            )
        case .tempBasal:
            return closeEnough(
                expected: pending.dose.programmedUnits,
                actual: eventDose.programmedUnits,
                tolerance: basalTolerance
            )
        case .resume,
             .suspend:
            return true
        default:
            return false
        }
    }

    private func closeEnough(expected: Double, actual: Double, tolerance: Double) -> Bool {
        abs(expected - actual) <= tolerance
    }
}
