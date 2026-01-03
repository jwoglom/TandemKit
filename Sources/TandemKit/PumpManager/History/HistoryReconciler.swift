import Foundation
import LoopKit

/// Matches locally-tracked pending doses with history-derived pump events.
class HistoryReconciler {
    private let matchWindow: TimeInterval = 5 * 60
    private let bolusTolerance: Double = 0.05
    private let basalTolerance: Double = 0.01
    private let uncertainAge: TimeInterval = 24 * 60 * 60

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
            guard var dose = event.dose else {
                reconciledEvents.append(event)
                continue
            }

            if let matchIndex = remainingPending.firstIndex(where: { matches($0, to: dose) }) {
                dose.syncIdentifier = remainingPending[matchIndex].syncIdentifier
                remainingPending.remove(at: matchIndex)
                let updatedEvent = NewPumpEvent(
                    date: event.date,
                    dose: dose,
                    isMutable: event.isMutable,
                    raw: event.raw,
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
                expected: pending.dose.deliveredUnits ?? pending.dose.value,
                actual: eventDose.deliveredUnits ?? eventDose.value,
                tolerance: bolusTolerance
            )
        case .tempBasal:
            return closeEnough(
                expected: pending.dose.value,
                actual: eventDose.value,
                tolerance: basalTolerance
            )
        case .suspend, .resume:
            return true
        default:
            return false
        }
    }

    private func closeEnough(expected: Double, actual: Double, tolerance: Double) -> Bool {
        abs(expected - actual) <= tolerance
    }
}
