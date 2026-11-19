import Foundation
import LoopKit

/// Reports history boluses the live path didn't report or couldn't finish (#354), extended parts,
/// and the pump's own suspends and resumes (`TandemPumpManager+DeliveryTransitions`), and compares
/// the basal it delivered with what the host was told (`TandemPumpManager+BasalReconciliation`).
extension TandemPumpManager {
    func reportHistoryDoses(after outcome: HistoryBackfillCoordinator.TickOutcome, now: Date) {
        guard state.featureFlags.historyBackfill, let serial = historyLogStoreSerial else {
            return
        }

        // A command job, so it cannot interleave with the live path reporting the same dose.
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Deferring history dose reporting to the next tick: \(error.localizedDescription)")
                self.reconciliationLog.recordSkippedPass(startedAt: outcome.startedAt, reason: error.localizedDescription, at: self.now)
                return
            }
            self.reconciliationLog.begin(outcome, at: self.now)
            var batch = self.reportHistoryDeliveryTransitions(after: outcome, pumpSerial: serial)
            self.reconciliationLog.current?.transitionsReported = batch.events.count
            self.reconcileBasalHistory(after: outcome, pumpSerial: serial, into: &batch)
            self.emitHistoryReports(batch)
            if self.state.featureFlags.historyDoseReporting, let covered = outcome.sessionCovered {
                self.reportHistoryBoluses(in: covered, pumpSerial: serial, floor: outcome.emitFloor, now: now)
            }
            self.reconciliationLog.end(at: self.now)
            if !self.isAwaitingHistory {
                self.releaseHistoryWaiters()
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
                .filter { Self.bolusHistoryTypes.contains($0.typeId) }
                .map { $0.parsed() }
        } catch {
            logger.error("Could not read the history log store for dose reporting: \(error)")
            return
        }

        state.bolusReportLedger.prune(now: now)
        let ledger = state.bolusReportLedger

        let dates = historyRecordDates(logs)
        let events = HistoryToDoseMapper().mapToEvents(
            dates.logs,
            dates: dates,
            pumpSerial: serial,
            insulinType: state.insulinType,
            isCommandedBolus: { ledger.entry(bolusId: $0, pumpSerial: serial.rawValue)?.origin == .commanded }
        )

        var reports: [NewPumpEvent] = []
        var finalizesHeldDose = false
        for event in events {
            guard let dose = event.dose, dose.type == .bolus, dose.startDate >= floor,
                  let decoded = HistoryLogSyncIdentifier.decode(event.raw)
            else {
                continue
            }
            let bolusId = Int(decoded.identifier)
            switch decoded.scheme {
            case .bolus:
                // Only once its completion is read: a pump bolus runs for seconds, and reported while it
                // ran it would have to ride every replacing batch until then, or the host deletes it (#452).
                guard !dose.isMutable else {
                    continue
                }
                let isHeld = state.bolusReportLedger.entry(bolusId: bolusId, pumpSerial: serial.rawValue) != nil
                if let report = historyBolusReport(event, dose: dose, bolusId: bolusId, serial: serial) {
                    reports.append(report)
                    finalizesHeldDose = finalizesHeldDose || isHeld
                }
            case .extendedBolus:
                let held = state.bolusReportLedger.entry(bolusId: bolusId, pumpSerial: serial.rawValue, part: .extended)
                if let report = extendedPartReport(event, dose: dose, bolusId: bolusId, held: held, serial: serial) {
                    reports.append(report)
                    finalizesHeldDose = finalizesHeldDose || held != nil
                }
            case .tempRate, .tempRatePart, .logSequence:
                continue
            }
        }

        guard !reports.isEmpty else {
            return
        }

        logger.info("Reporting \(reports.count) bolus event(s) from pump history")
        reconciliationLog.current?.bolusesReported = reports.count
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

    private static let bolusHistoryTypes = Set([
        BolusActivatedHistoryLog.typeId,
        BolusCompletedHistoryLog.typeId,
        BolusDeliveryHistoryLog.typeId,
        BolusRequestedMsg2HistoryLog.typeId,
        BolexActivatedHistoryLog.typeId,
        BolexCompletedHistoryLog.typeId
    ] + HistoryTimestampReconciler.clockHistoryTypes)

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
                isFinalized: false,
                units: dose.deliveredUnits ?? dose.programmedUnits
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

        return Self.reported(dose, as: entry, title: event.title)
    }

    /// Reported mutable once its BolexActivated is read, since it can run for hours; every replacing batch
    /// carries it until its BolexCompleted finalizes it in one.
    private func extendedPartReport(
        _ event: NewPumpEvent,
        dose: DoseEntry,
        bolusId: Int,
        held: BolusReportLedger.Entry?,
        serial: HistoryLogSyncIdentifier.PumpSerial
    ) -> NewPumpEvent? {
        guard let held else {
            state.bolusReportLedger.record(BolusReportLedger.Entry(
                bolusId: bolusId,
                pumpSerial: serial.rawValue,
                origin: .history,
                part: .extended,
                raw: event.raw,
                eventDate: event.date,
                automatic: dose.automatic ?? false,
                isFinalized: false,
                units: dose.deliveredUnits ?? dose.programmedUnits,
                programmedEndDate: dose.isMutable ? dose.endDate : nil
            ))
            return event
        }
        guard !held.isFinalized, !dose.isMutable else {
            return nil
        }
        return Self.reported(dose, as: held, title: event.title)
    }

    /// A held part whose BolexCompleted is still unread `extendedPartFinalizationWindow` after its programmed
    /// end is finalized at its programmed amount, what the host counted: history may never show its end.
    func heldExtendedPartEvents() -> [NewPumpEvent] {
        state.bolusReportLedger.heldExtendedParts.map { entry in
            let end = entry.programmedEndDate ?? entry.eventDate
            let isOverdue = now.timeIntervalSince(end) > Self.extendedPartFinalizationWindow
            return extendedPartEvent(entry, end: end, deliveredUnits: isOverdue ? entry.units ?? 0 : nil)
        }
    }

    /// Loop stores a finalized dose only once it has ended, and never replaces a mutable copy it dropped
    /// before then, so a part still running is finalized to the deletion under its own identity and the
    /// rest, which the pump goes on delivering, is a finalized dose of its own to the programmed end.
    func deactivatedExtendedPartEvents() -> [NewPumpEvent] {
        state.bolusReportLedger.heldExtendedParts.flatMap { entry -> [NewPumpEvent] in
            let units = entry.units ?? 0
            let end = entry.programmedEndDate ?? entry.eventDate
            // A second on at least: Trio matches a new row on its timestamp.
            let cut = max(now, entry.eventDate.addingTimeInterval(1))
            guard cut < end else {
                return [extendedPartEvent(entry, end: end, deliveredUnits: units)]
            }
            let ranSoFar = TandemPumpCapabilities.roundToReportingResolution(
                units * cut.timeIntervalSince(entry.eventDate) / end.timeIntervalSince(entry.eventDate)
            )
            let rest = TandemPumpCapabilities.roundToReportingResolution(units - ranSoFar)
            let remainder = DoseEntry(
                type: .bolus,
                startDate: cut,
                endDate: end,
                value: rest,
                unit: .units,
                decisionId: nil,
                deliveredUnits: rest,
                description: "Extended bolus #\(entry.bolusId)",
                insulinType: state.insulinType,
                automatic: entry.automatic,
                wasProgrammedByPumpUI: entry.origin == .history
            )
            return [
                extendedPartEvent(entry, end: cut, deliveredUnits: ranSoFar),
                NewPumpEvent(date: cut, dose: remainder, raw: NewPumpEvent.bolus(dose: remainder, date: cut).raw, title: "Extended Bolus", type: .bolus)
            ]
        }
    }

    /// Mutable while `deliveredUnits` is nil.
    private func extendedPartEvent(_ entry: BolusReportLedger.Entry, end: Date, deliveredUnits: Double?) -> NewPumpEvent {
        let dose = DoseEntry(
            type: .bolus,
            startDate: entry.eventDate,
            endDate: end,
            value: entry.units ?? 0,
            unit: .units,
            decisionId: nil,
            deliveredUnits: deliveredUnits,
            description: "Extended bolus #\(entry.bolusId)",
            syncIdentifier: entry.raw.hexadecimalString,
            insulinType: state.insulinType,
            automatic: entry.automatic,
            isMutable: deliveredUnits == nil,
            wasProgrammedByPumpUI: entry.origin == .history
        )
        return NewPumpEvent(date: entry.eventDate, dose: dose, raw: entry.raw, title: "Extended Bolus", type: .bolus)
    }

    static let extendedPartFinalizationWindow: TimeInterval = .hours(1)

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
    private static func reported(_ dose: DoseEntry, as entry: BolusReportLedger.Entry, title: String) -> NewPumpEvent {
        let rekeyed = DoseEntry(
            type: .bolus,
            startDate: dose.startDate,
            endDate: dose.endDate,
            value: dose.programmedUnits,
            unit: .units,
            decisionId: entry.decisionId,
            deliveredUnits: dose.deliveredUnits,
            description: dose.description,
            syncIdentifier: entry.raw.hexadecimalString,
            insulinType: dose.insulinType,
            automatic: entry.automatic,
            isMutable: dose.isMutable,
            wasProgrammedByPumpUI: entry.origin == .history
        )
        return NewPumpEvent(date: entry.eventDate, dose: rekeyed, raw: entry.raw, title: title, type: .bolus)
    }
}
