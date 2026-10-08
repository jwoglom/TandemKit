import Foundation
import LoopKit

/// Reports history boluses the live path didn't report or couldn't finish (#354), and the pump's
/// own suspends and resumes (`TandemPumpManager+DeliveryTransitions`).
extension TandemPumpManager {
    func reportHistoryDoses(after outcome: HistoryBackfillCoordinator.TickOutcome, now: Date) {
        guard state.featureFlags.historyBackfill, let serial = historyLogStoreSerial else {
            return
        }

        // A command job, so it cannot interleave with the live path reporting the same dose.
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Deferring history dose reporting to the next tick: \(error.localizedDescription)")
                return
            }
            self.reportHistoryDeliveryTransitions(after: outcome, pumpSerial: serial)
            if self.state.featureFlags.historyDoseReporting, let covered = outcome.sessionCovered {
                self.reportHistoryBoluses(in: covered, pumpSerial: serial, floor: outcome.emitFloor, now: now)
            }
        }
    }

    func reportHistoryBoluses(
        in covered: ClosedRange<UInt32>,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial,
        floor: Date,
        now: Date
    ) {
        let logs: [HistoryLog]
        do {
            logs = try historyLogStore.logs(pumpSerial: serial.rawValue, in: covered)
                .map { $0.parsed() }
                .filter(Self.isReportedBolusInput)
        } catch {
            logger.error("Could not read the history log store for dose reporting: \(error)")
            return
        }

        for bolex in logs.compactMap({ $0 as? BolexActivatedHistoryLog }) {
            logger.warning("Extended bolus \(bolex.bolusId) in pump history is not reported to the app")
        }

        state.bolusReportLedger.prune(now: now)
        let ledger = state.bolusReportLedger

        let events = HistoryToDoseMapper().mapToEvents(
            logs,
            dates: historyRecordDates(logs),
            pumpSerial: serial,
            insulinType: state.insulinType,
            isCommandedBolus: { ledger.entry(bolusId: $0, pumpSerial: serial.rawValue)?.origin == .commanded }
        )

        var reports: [NewPumpEvent] = []
        var finalizesHeldDose = false
        for event in events {
            // Only once its completion is read: reported while it ran, a pump bolus would have to
            // ride every replacing batch until then, or the host deletes it (#452).
            guard let dose = event.dose, dose.type == .bolus, !dose.isMutable, dose.startDate >= floor,
                  let decoded = HistoryLogSyncIdentifier.decode(event.raw), decoded.scheme == .bolus
            else {
                continue
            }
            let bolusId = Int(decoded.identifier)
            let isHeld = state.bolusReportLedger.entry(bolusId: bolusId, pumpSerial: serial.rawValue) != nil
            if let report = historyBolusReport(event, dose: dose, bolusId: bolusId, serial: serial) {
                reports.append(report)
                finalizesHeldDose = finalizesHeldDose || isHeld
            }
        }

        guard !reports.isEmpty else {
            return
        }

        logger.info("Reporting \(reports.count) bolus event(s) from pump history")
        let sorted = reports.sorted { $0.date < $1.date }
        // Loop keeps a stored PumpEvent row over a non-replacing report with its raw, so finalizing
        // a dose the host holds as mutable takes a replacing batch (#452).
        if finalizesHeldDose {
            emitPumpEvents(getActivePumpEvents() + sorted)
        } else {
            emitPumpEvents(sorted, replacePendingEvents: false)
        }
        notifyDelegateStateUpdated()
    }

    private static func isReportedBolusInput(_ log: HistoryLog) -> Bool {
        switch log {
        case is BolusActivatedHistoryLog, is BolusCompletedHistoryLog, is BolusDeliveryHistoryLog,
             is BolusRequestedMsg2HistoryLog, is BolexActivatedHistoryLog,
             is TimeChangedHistoryLog, is DateChangeHistoryLog:
            return true
        default:
            return false
        }
    }

    private func historyBolusReport(
        _ event: NewPumpEvent,
        dose: DoseEntry,
        bolusId: Int,
        serial: HistoryLogSyncIdentifier.PumpSerial
    ) -> NewPumpEvent? {
        guard let entry = state.bolusReportLedger.entry(bolusId: bolusId, pumpSerial: serial.rawValue) else {
            state.bolusReportLedger.record(BolusReportLedger.Entry(
                bolusId: bolusId,
                pumpSerial: serial.rawValue,
                origin: .history,
                raw: event.raw,
                eventDate: event.date,
                automatic: dose.automatic ?? false,
                isFinalized: false
            ))
            return event
        }

        guard !entry.isFinalized else {
            return nil
        }

        if entry.origin == .commanded {
            guard !isTrackingBolusLive(bolusId) else {
                return nil
            }
            releaseLiveBolusState(bolusId)
        }

        return Self.reported(dose, as: entry)
    }

    private func isTrackingBolusLive(_ bolusId: Int) -> Bool {
        bolusProgressReport != nil && state.bolusDose?.bolusId == bolusId
    }

    private func releaseLiveBolusState(_ bolusId: Int) {
        if state.pendingBolusFinalization?.bolusId == bolusId {
            state.pendingBolusFinalization = nil
        }
        if state.bolusDose?.bolusId == bolusId {
            state.bolusDose = nil
            state.bolusState = .noBolus
        }
    }

    /// Under the host's existing identity and date, so it updates that row instead of adding one.
    private static func reported(_ dose: DoseEntry, as entry: BolusReportLedger.Entry) -> NewPumpEvent {
        let rekeyed = DoseEntry(
            type: .bolus,
            startDate: dose.startDate,
            endDate: dose.endDate,
            value: dose.programmedUnits,
            unit: .units,
            deliveredUnits: dose.deliveredUnits,
            description: dose.description,
            syncIdentifier: entry.raw.hexadecimalString,
            insulinType: dose.insulinType,
            automatic: entry.automatic,
            isMutable: dose.isMutable,
            wasProgrammedByPumpUI: entry.origin == .history
        )
        return NewPumpEvent(date: entry.eventDate, dose: rekeyed, raw: entry.raw, title: "Bolus", type: .bolus)
    }
}
