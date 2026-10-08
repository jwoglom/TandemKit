import Foundation
import LoopKit

/// Suspends, resumes and temp basal ends the pump made on its own, dated from its history log
/// rather than from the reading that noticed them (#333, #331).
///
/// Neither host revises one once told: Trio keeps a row per (timestamp, type), and Loop never
/// counts a non-bolus dose older than its last finished basal (#354). So the first report must
/// carry the pump's date, and must reach the host before anything the app commands after it.
/// Behind `historyBackfill` a change is left pending for the next history pass; a sync that saw it
/// waits for that pass, and an app command reports it first. Without the flag, or without the
/// pump's record, it is reported at detection, each end dated the way that counts more insulin.
extension TandemPumpManager {
    typealias PendingTransition = DeliveryTransitionLedger.PendingTransition

    /// Where the pump's record of a transition the driver reported lands, around the report.
    static let transitionMatchTolerance: TimeInterval = .minutes(1)

    var datesTransitionsFromHistory: Bool {
        state.featureFlags.historyBackfill && historyLogStoreSerial != nil
    }

    static func isSameDelivery(_ observed: DoseType, as held: DoseType) -> Bool {
        observed == held || (observed == .basal && held == .resume)
    }

    func recordReportedTransition(
        _ kind: DeliveryTransitionLedger.Kind,
        at date: Date,
        earliest: Date? = nil,
        latest: Date? = nil,
        sequenceNum: UInt32? = nil
    ) {
        let tolerance = Self.transitionMatchTolerance
        state.deliveryTransitions.prune(before: now.addingTimeInterval(-DeliveryTransitionLedger.retention))
        state.deliveryTransitions.record(DeliveryTransitionLedger.Entry(
            kind: kind,
            date: date,
            earliest: earliest ?? date.addingTimeInterval(-tolerance),
            latest: latest ?? date.addingTimeInterval(tolerance),
            sequenceNum: sequenceNum,
            isReported: true
        ))
        let confirmed = state.deliveryTransitions.lastConfirmedObservation ?? .distantPast
        state.deliveryTransitions.lastConfirmedObservation = max(confirmed, date)
    }

    /// Every `CurrentBasalStatus` reading. Returns whether a change is now waiting for history.
    @discardableResult
    func observeDeliveryState(_ observed: DoseType) -> Bool {
        let now = self.now
        if let pending = state.deliveryTransitions.pending {
            if datesTransitionsFromHistory, Self.isSameDelivery(observed, as: pending.observed) {
                state.deliveryTransitions.lastConfirmedObservation = now
                return true
            }
            logger.warning("Reporting the \(pending.observed) seen at \(pending.detectedAt) at detection; the pump now reports \(observed)")
            reportTransition(pending)
        }

        let held = state.basalDose
        if Self.isSameDelivery(observed, as: held.type) {
            state.deliveryTransitions.lastConfirmedObservation = now
            return false
        }
        // A temp rate the app did not set is not reported.
        guard held.type == .suspend || held.type == .tempBasal || observed == .suspend else {
            return false
        }

        let pending = PendingTransition(
            prior: held,
            observed: observed,
            detectedAt: now,
            lastConfirmed: max(held.startDate, state.deliveryTransitions.lastConfirmedObservation ?? .distantPast)
        )
        state.deliveryTransitions.lastConfirmedObservation = now
        guard datesTransitionsFromHistory else {
            reportTransition(pending)
            return false
        }

        logger.info("Pump reports \(observed) where \(held.type) was reported; dating the change from pump history")
        state.deliveryTransitions.pending = pending
        state.basalDose = placeholderDose(for: pending)
        notifyDelegateStateUpdated()
        return true
    }

    func historyTickFailed(startedAt: Date) {
        bluetooth.ensureConnected { _ in
            guard let pending = self.state.deliveryTransitions.pending, startedAt >= pending.detectedAt else { return }
            self.logger.warning("Pump history could not be read; reporting the \(pending.observed) seen at \(pending.detectedAt) at detection")
            self.reportTransition(pending)
        }
    }

    /// Before anything the host must hear of after the change: an app command, or a sync's result.
    func settleDeliveryTransition() {
        guard let pending = state.deliveryTransitions.pending else { return }
        logger.warning("Reporting the \(pending.observed) seen at \(pending.detectedAt) at detection")
        reportTransition(pending)
    }

    /// For status only; the host still holds `prior`.
    private func placeholderDose(for pending: PendingTransition) -> UnfinalizedDose {
        if pending.observed == .suspend {
            return UnfinalizedDose(suspendStartTime: pending.detectedAt)
        }
        if pending.prior.type == .suspend {
            return UnfinalizedDose(resumeStartTime: pending.detectedAt, insulinType: state.insulinType)
        }
        return UnfinalizedDose(basalRate: getScheduledBasalRate(), insulinType: state.insulinType, startDate: pending.detectedAt)
    }

    /// The last suspend or resume the host holds before `date`. The ledger misses one reported
    /// before it existed or pruned since; the dose the host holds does not.
    func hostTransition(before date: Date) -> (kind: DeliveryTransitionLedger.Kind, date: Date)? {
        let recorded = state.deliveryTransitions.lastReported(before: date).map { (kind: $0.kind, date: $0.date) }
        let held = state.deliveryTransitions.pending?.prior ?? state.basalDose
        let heldKind: DeliveryTransitionLedger.Kind? = switch held.type {
        case .suspend: .suspend
        case .resume: .resume
        default: nil
        }
        guard let heldKind, held.startDate < date, (recorded?.date ?? .distantPast) < held.startDate else {
            return recorded
        }
        return (heldKind, held.startDate)
    }

    /// Reports what `pending` leaves unsaid after `events`, the history pass's reports. Without the
    /// pump's record each end is dated the way that counts more insulin.
    func reportTransition(_ pending: PendingTransition, tempRateEnd: Date? = nil, events: [NewPumpEvent] = []) {
        let prior = pending.prior
        let tolerance = Self.transitionMatchTolerance
        let earliest = pending.lastConfirmed.addingTimeInterval(-tolerance)
        let latest = pending.detectedAt.addingTimeInterval(tolerance)
        var events = events

        var tempBasalEnd: Date?
        if prior.type == .tempBasal {
            let lastSeen = splitAtSegmentChanges(prior, through: pending.lastConfirmed).running
            // Against the schedule the host counts after it, on the phone's clock.
            let end = tempRateEnd ?? (lastSeen.value < getScheduledBasalRate(at: lastSeen.startDate) ? pending.lastConfirmed : pending.detectedAt)
            let endDate = max(min(end, pending.detectedAt), prior.startDate)
            let (finished, last) = splitAtSegmentChanges(prior, through: endDate)
            let entry = last.toDoseEntry(isMutable: false, endDate: max(endDate, last.startDate), now: now)
            events += finished
            events.append(NewPumpEvent.tempBasal(dose: entry, date: entry.startDate))
            tempBasalEnd = entry.endDate
        }

        let final: UnfinalizedDose
        switch (pending.observed == .suspend, hostTransition(before: .distantFuture)) {
        case let (true, host?) where host.kind == .suspend:
            final = UnfinalizedDose(suspendStartTime: host.date)
        case (true, _):
            final = UnfinalizedDose(suspendStartTime: pending.detectedAt)
            events.append(NewPumpEvent.suspend(dose: final.toDoseEntry(), date: final.startDate))
            recordReportedTransition(.suspend, at: final.startDate, earliest: earliest, latest: latest)
        case let (false, host?) where host.kind == .suspend:
            final = UnfinalizedDose(resumeStartTime: max(pending.lastConfirmed, host.date.addingTimeInterval(1)), insulinType: state.insulinType)
            events.append(NewPumpEvent.resume(dose: final.toDoseEntry(), date: final.startDate))
            recordReportedTransition(.resume, at: final.startDate, earliest: earliest, latest: latest)
        case let (false, host?) where host.kind == .resume && host.date > prior.startDate:
            final = UnfinalizedDose(resumeStartTime: host.date, insulinType: state.insulinType)
        default:
            let start = tempBasalEnd ?? pending.detectedAt
            final = UnfinalizedDose(basalRate: getScheduledBasalRate(at: start), insulinType: state.insulinType, startDate: start)
            events.append(NewPumpEvent.basal(dose: final.toDoseEntry(), date: final.startDate))
        }

        logger.info("Reporting the \(pending.observed) seen at \(pending.detectedAt): \(events.count) event(s)")
        state.deliveryTransitions.pending = nil
        state.basalDose = final
        state.lastReconciliation = now
        events.sort { $0.date < $1.date }
        if !events.isEmpty {
            // The finished temp basal is re-keyed (#344), so only a replacing batch retires the
            // mutable row the host holds.
            emitPumpEvents(events, replacePendingEvents: events.contains { $0.dose?.type == .tempBasal })
        }
        notifyDelegateStateUpdated()
        deliveryTransitionReported()
    }

    // MARK: - History pass

    private struct PumpTransition {
        let sequenceNum: UInt32
        let kind: DeliveryTransitionLedger.Kind
        let date: Date
    }

    /// Reports the pump's suspends and resumes the host was never given, at the pump's time, and
    /// resolves a pending change once the tick has read the log past it.
    func reportHistoryDeliveryTransitions(
        after outcome: HistoryBackfillCoordinator.TickOutcome,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial
    ) {
        guard let pumpRange = outcome.pumpSequenceRange else { return }
        // From the pump's status, even when the read after it failed, so a change in the meantime counts.
        if !state.deliveryTransitions.isTracking(pumpSerial: serial.rawValue, lastSequenceNum: pumpRange.upperBound) {
            logger.info("Tracking delivery changes on pump \(serial.rawValue) after record \(pumpRange.upperBound)")
            state.deliveryTransitions.track(pumpSerial: serial.rawValue, after: pumpRange.upperBound)
        }
        guard let trackedAfter = state.deliveryTransitions.trackedAfter else { return }
        guard let covered = outcome.sessionCovered else {
            if let pending = state.deliveryTransitions.pending, outcome.startedAt >= pending.detectedAt {
                logger.warning("Pump history was not read; reporting the \(pending.observed) seen at \(pending.detectedAt) at detection")
                reportTransition(pending)
            }
            return
        }

        let stored: [HistoryLog]
        do {
            stored = try historyLogStore.logs(pumpSerial: serial.rawValue, in: covered)
                .map { $0.parsed() }
                .sorted { $0.sequenceNum < $1.sequenceNum }
        } catch {
            logger.error("Could not read the history log store for delivery transitions: \(error)")
            return
        }

        let dates = historyRecordDates(stored)

        let now = self.now
        let floor = now.addingTimeInterval(-DeliveryTransitionLedger.retention)
        let tolerance = Self.transitionMatchTolerance
        state.deliveryTransitions.prune(before: floor)

        if let pending = state.deliveryTransitions.pending {
            guard outcome.startedAt >= pending.detectedAt else {
                logger.info("Waiting for a tick that started after the \(pending.observed) seen at \(pending.detectedAt)")
                return
            }
            let reachesBack = outcome.isDeepBackfillComplete || outcome.reachesPumpStart
                || stored.first.map { dates.phoneDate(of: $0) <= pending.lastConfirmed } == true
            guard outcome.readsThroughPumpEnd, reachesBack else {
                logger.warning("Pump history does not cover the \(pending.observed) seen at \(pending.detectedAt); reporting it at detection")
                reportTransition(pending)
                return
            }
        }

        var records: [PumpTransition] = []
        var tempRateEnds: [Int: (date: Date, ranToEnd: Bool)] = [:]
        for log in stored {
            switch log {
            case is PumpingSuspendedHistoryLog where log.sequenceNum > trackedAfter:
                records.append(PumpTransition(sequenceNum: log.sequenceNum, kind: .suspend, date: dates.phoneDate(of: log)))
            case is PumpingResumedHistoryLog where log.sequenceNum > trackedAfter:
                records.append(PumpTransition(sequenceNum: log.sequenceNum, kind: .resume, date: dates.phoneDate(of: log)))
            case let completed as TempRateCompletedHistoryLog:
                tempRateEnds[completed.tempRateId] = (dates.phoneDate(of: completed), completed.timeLeft == 0)
            default:
                continue
            }
        }
        records.removeAll { $0.date < floor || $0.date > now.addingTimeInterval(tolerance) }

        let isSuspendedNow = (state.deliveryTransitions.pending?.observed ?? state.basalDose.type) == .suspend
        func leaveUnreported(_ record: PumpTransition) {
            state.deliveryTransitions.record(DeliveryTransitionLedger.Entry(
                kind: record.kind,
                date: record.date,
                earliest: record.date,
                latest: record.date,
                sequenceNum: record.sequenceNum,
                isReported: false
            ))
        }

        // A record skipped without an entry is reconsidered next pass: one the host view rules out
        // may belong to a pair whose other half is in a gap the next tick fills.
        var events: [NewPumpEvent] = []
        for record in records where !state.deliveryTransitions.isHandled(sequenceNum: record.sequenceNum) {
            if state.deliveryTransitions.match(record.kind, at: record.date, sequenceNum: record.sequenceNum) {
                continue
            }
            switch record.kind {
            case .suspend:
                let resume = records.first { $0.sequenceNum > record.sequenceNum && $0.kind == .resume }
                if let resume, resume.date.timeIntervalSince(record.date) < 1 {
                    // Trio's IOB throws on a suspend and resume in the same second.
                    leaveUnreported(record)
                    if !state.deliveryTransitions.isHandled(sequenceNum: resume.sequenceNum) {
                        leaveUnreported(resume)
                    }
                    continue
                }
                // Trio takes a trailing suspend as lasting until now; Loop keeps only the later of
                // two suspends in a row.
                guard resume != nil || isSuspendedNow, hostTransition(before: record.date)?.kind != .suspend else {
                    continue
                }
                let dose = UnfinalizedDose(suspendStartTime: record.date)
                events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate))
                recordReportedTransition(.suspend, at: record.date, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)

            case .resume:
                // Trio takes a resume with no suspend before it as suspended until the resume.
                guard let host = hostTransition(before: record.date), host.kind == .suspend else {
                    continue
                }
                let dose = UnfinalizedDose(resumeStartTime: max(record.date, host.date.addingTimeInterval(1)), insulinType: state.insulinType)
                events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate))
                recordReportedTransition(.resume, at: dose.startDate, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)
            }
        }

        guard let pending = state.deliveryTransitions.pending else {
            if !events.isEmpty {
                logger.info("Reporting \(events.count) suspend/resume event(s) from pump history")
                emitPumpEvents(events, replacePendingEvents: false)
            }
            notifyDelegateStateUpdated()
            return
        }

        let window = pending.lastConfirmed.addingTimeInterval(-tolerance) ... pending.detectedAt.addingTimeInterval(tolerance)
        let scheduledEnd = pending.prior.estimatedEndDate
        let tempRateEnd = pending.prior.tempRateId.flatMap { tempRateEnds[$0] }.map { completion in
            // One that ran out ends exactly when programmed, so it keeps the identity it was reported under (#344).
            completion.ranToEnd && abs(completion.date.timeIntervalSince(scheduledEnd)) <= tolerance ? scheduledEnd : completion.date
        } ?? records.first { $0.kind == .suspend && $0.date > pending.prior.startDate && window.contains($0.date) }?.date
        reportTransition(pending, tempRateEnd: tempRateEnd, events: events)
    }
}
