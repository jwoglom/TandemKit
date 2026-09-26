import Foundation
import LoopKit

/// Suspends, resumes and temp basal ends the pump made on its own, dated from its history log
/// rather than from the poll that noticed them (#333). Behind `historyBackfill`; while it is off,
/// `fetchBasalStatus` reports them at detection, as before.
///
/// Neither host revises a finished suspend, resume or temp basal, so the live path does not report
/// one it did not command: it leaves it pending and the next history pass reports it at the pump's
/// time. Two suspends in a row would also be wrong in Loop, which keeps only the second open.
extension TandemPumpManager {
    /// Where the pump's record of a transition the app commanded lands, around the report.
    static let transitionMatchTolerance: TimeInterval = .minutes(1)
    /// How long a change the live path saw waits for history before it is reported at detection.
    static let historyTransitionDeadline: TimeInterval = .minutes(15)

    var datesTransitionsFromHistory: Bool {
        state.featureFlags.historyBackfill && historyLogStoreSerial != nil
    }

    static func isSameDelivery(_ observed: DoseType, as reported: DoseType) -> Bool {
        observed == reported || (observed == .basal && reported == .resume)
    }

    func recordReportedTransition(
        _ kind: DeliveryTransitionLedger.Kind,
        at date: Date,
        earliest: Date? = nil,
        latest: Date? = nil,
        sequenceNum: UInt32? = nil
    ) {
        let tolerance = Self.transitionMatchTolerance
        state.deliveryTransitions.prune(now: now)
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

    /// The live path's view of the pump's delivery state, from `CurrentBasalStatus`.
    func observeDeliveryState(_ observed: DoseType, now: Date) {
        if var pending = state.deliveryTransitions.pending {
            guard now.timeIntervalSince(pending.detectedAt) < Self.historyTransitionDeadline else {
                logger.warning("Pump history never dated the \(pending.observed) seen at \(pending.detectedAt); reporting it at detection")
                reportTransitionAtDetection(pending)
                observeDeliveryState(observed, now: now)
                return
            }
            if !Self.isSameDelivery(observed, as: state.basalDose.type), isPlaceholder(for: pending) {
                pending.observed = observed
                state.deliveryTransitions.pending = pending
                state.basalDose = placeholderDose(for: observed, prior: pending.prior, at: pending.detectedAt)
                notifyDelegateStateUpdated()
            }
            historyBackfillCoordinator.runTick()
            return
        }

        let prior = state.basalDose
        if Self.isSameDelivery(observed, as: prior.type) {
            state.deliveryTransitions.lastConfirmedObservation = now
            return
        }
        // A temp rate the app did not set is not reported, as before.
        guard prior.type == .suspend || observed == .suspend || prior.type == .tempBasal else {
            return
        }

        logger.info("Pump reports \(observed) where \(prior.type) was reported; dating the change from pump history")
        state.deliveryTransitions.pending = DeliveryTransitionLedger.PendingTransition(
            prior: prior,
            observed: observed,
            detectedAt: now,
            lastConfirmed: max(prior.startDate, state.deliveryTransitions.lastConfirmedObservation ?? .distantPast)
        )
        state.basalDose = placeholderDose(for: observed, prior: prior, at: now)
        notifyDelegateStateUpdated()
        historyBackfillCoordinator.runTick()
    }

    /// For status only: never reported to the host.
    private func placeholderDose(for observed: DoseType, prior: UnfinalizedDose, at date: Date) -> UnfinalizedDose {
        if observed == .suspend {
            return UnfinalizedDose(suspendStartTime: date)
        }
        if prior.type == .suspend {
            return UnfinalizedDose(resumeStartTime: date, insulinType: state.insulinType)
        }
        return UnfinalizedDose(basalRate: getScheduledBasalRate(), insulinType: state.insulinType, startDate: date)
    }

    /// False once an app command has replaced the placeholder.
    private func isPlaceholder(for pending: DeliveryTransitionLedger.PendingTransition) -> Bool {
        state.basalDose.startDate == pending.detectedAt
    }

    /// Without the pump's record, each end is dated the way that counts more insulin, not less.
    func reportTransitionAtDetection(_ pending: DeliveryTransitionLedger.PendingTransition) {
        state.deliveryTransitions.pending = nil
        let tolerance = Self.transitionMatchTolerance
        let earliest = pending.lastConfirmed.addingTimeInterval(-tolerance)
        let latest = pending.detectedAt.addingTimeInterval(tolerance)
        let prior = pending.prior
        var events: [NewPumpEvent] = []
        var finalDose: UnfinalizedDose?

        var tempBasalEnd: Date?
        if prior.type == .tempBasal {
            let end = prior.value < getScheduledBasalRate(at: prior.startDate) ? pending.lastConfirmed : pending.detectedAt
            let finished = finishedTempBasal(prior, at: end)
            events.append(finished)
            tempBasalEnd = finished.dose?.endDate
        }

        if pending.observed == .suspend, prior.type != .suspend {
            let dose = UnfinalizedDose(suspendStartTime: pending.detectedAt)
            events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate))
            recordReportedTransition(.suspend, at: dose.startDate, earliest: earliest, latest: latest)
            finalDose = dose
        } else if pending.observed != .suspend, prior.type == .suspend {
            let resumeAt = max(pending.lastConfirmed, prior.startDate.addingTimeInterval(1))
            let dose = UnfinalizedDose(resumeStartTime: resumeAt, insulinType: state.insulinType)
            events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate))
            recordReportedTransition(.resume, at: dose.startDate, earliest: earliest, latest: latest)
            finalDose = dose
        } else if let tempBasalEnd {
            let dose = scheduledBasal(from: tempBasalEnd)
            events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))
            finalDose = dose
        }

        finish(pending, finalDose: finalDose, events: events)
    }

    // MARK: - History pass

    private struct PumpTransition {
        let sequenceNum: UInt32
        let kind: DeliveryTransitionLedger.Kind
        let date: Date
    }

    /// Reports the pump's suspends and resumes the host was never given, at the pump's time, and
    /// resolves a pending change once history reaches it.
    ///
    /// - Parameters:
    ///   - completeThrough: The instant up to which the pump's log has been read in full, or nil.
    ///   - reachesBack: Whether the session store holds everything a pending change can need.
    func reportHistoryDeliveryTransitions(
        in covered: ClosedRange<UInt32>,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial,
        floor: Date,
        completeThrough: Date?,
        reachesBack: Bool,
        now: Date
    ) {
        let stored: [HistoryLog]
        do {
            stored = try historyLogStore.logs(pumpSerial: serial.rawValue, in: covered)
                .map { $0.parsed() }
                .sorted { $0.sequenceNum < $1.sequenceNum }
        } catch {
            logger.error("Could not read the history log store for delivery transitions: \(error)")
            return
        }

        state.deliveryTransitions.prune(now: now)
        let floor = max(floor, state.deliveryTransitions.trackingSince)
        let tolerance = Self.transitionMatchTolerance

        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: stored)
        // History is stamped on the pump's clock; the host's doses are on the phone's.
        let clockOffset = state.pumpClockOffset
        func phoneDate(_ log: HistoryLog) -> Date {
            reconciler.utcDate(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum).addingTimeInterval(-clockOffset)
        }

        var records: [PumpTransition] = []
        var tempRateEnds: [Int: Date] = [:]
        for log in stored {
            switch log {
            case is PumpingSuspendedHistoryLog:
                records.append(PumpTransition(sequenceNum: log.sequenceNum, kind: .suspend, date: phoneDate(log)))
            case is PumpingResumedHistoryLog:
                records.append(PumpTransition(sequenceNum: log.sequenceNum, kind: .resume, date: phoneDate(log)))
            case let completed as TempRateCompletedHistoryLog:
                tempRateEnds[completed.tempRateId] = phoneDate(completed)
            default:
                continue
            }
        }

        var unmatched: [PumpTransition] = []
        for record in records where record.date >= floor && !state.deliveryTransitions.isHandled(sequenceNum: record.sequenceNum) {
            if !state.deliveryTransitions.match(record.kind, at: record.date, sequenceNum: record.sequenceNum) {
                unmatched.append(record)
            }
        }

        let pending = state.deliveryTransitions.pending
        if let pending {
            let reachesPending = reachesBack || stored.first.map { phoneDate($0) <= pending.lastConfirmed } ?? false
            guard let completeThrough, completeThrough >= pending.detectedAt, reachesPending else {
                logger.info("Waiting for pump history to reach the \(pending.observed) seen at \(pending.detectedAt)")
                notifyDelegateStateUpdated()
                return
            }
        }

        let isSuspendedNow = (pending?.observed ?? state.basalDose.type) == .suspend
        var reported: [(kind: DeliveryTransitionLedger.Kind, date: Date)] = []
        func hostLast(before date: Date) -> (kind: DeliveryTransitionLedger.Kind, date: Date)? {
            let fromLedger = state.deliveryTransitions.lastReported(before: date).map { (kind: $0.kind, date: $0.date) }
            let fromPass = reported.last { $0.date < date }
            switch (fromLedger, fromPass) {
            case let (ledger?, pass?): return ledger.date > pass.date ? ledger : pass
            case let (ledger, pass): return ledger ?? pass
            }
        }
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

        var events: [NewPumpEvent] = []
        for record in unmatched {
            switch record.kind {
            case .suspend:
                if let resume = records.first(where: { $0.sequenceNum > record.sequenceNum && $0.kind == .resume }) {
                    // Trio cannot compute IOB over a suspend and resume stamped the same second.
                    if resume.date.timeIntervalSince(record.date) < 1 {
                        leaveUnreported(record)
                        continue
                    }
                } else if !isSuspendedNow {
                    // Its resume has not been read yet. Trio treats a trailing suspend as lasting until now.
                    continue
                }
                // Loop keeps only the later of two suspends in a row.
                if hostLast(before: record.date)?.kind == .suspend {
                    leaveUnreported(record)
                    continue
                }
                let dose = UnfinalizedDose(suspendStartTime: record.date)
                events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate))
                recordReportedTransition(.suspend, at: record.date, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)
                reported.append((.suspend, record.date))

            case .resume:
                // Trio treats a resume with no suspend before it as suspended until the resume.
                guard let last = hostLast(before: record.date), last.kind == .suspend else {
                    leaveUnreported(record)
                    continue
                }
                let date = max(record.date, last.date.addingTimeInterval(1))
                let dose = UnfinalizedDose(resumeStartTime: date, insulinType: state.insulinType)
                events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate))
                recordReportedTransition(.resume, at: date, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)
                reported.append((.resume, date))
            }
        }

        guard let pending else {
            guard !events.isEmpty else {
                notifyDelegateStateUpdated()
                return
            }
            logger.info("Reporting \(events.count) suspend/resume event(s) from pump history")
            emitPumpEvents(events, replacePendingEvents: false)
            notifyDelegateStateUpdated()
            return
        }

        let prior = pending.prior
        let window = pending.lastConfirmed.addingTimeInterval(-tolerance) ... pending.detectedAt.addingTimeInterval(tolerance)
        var tempBasalEnd: Date?
        if prior.type == .tempBasal {
            let pumpEnd = prior.tempRateId.flatMap { tempRateEnds[$0] }
                ?? records.first { $0.kind == .suspend && $0.date > prior.startDate && window.contains($0.date) }?.date
            let end = pumpEnd ?? (prior.value < getScheduledBasalRate(at: prior.startDate) ? pending.lastConfirmed : pending.detectedAt)
            let finished = finishedTempBasal(prior, at: min(end, pending.detectedAt))
            events.append(finished)
            tempBasalEnd = finished.dose?.endDate
        }

        // What the pump recorded in the gap decides the state, not the host's latest report: an app
        // command after the reconnect is not the change that was seen. Only records the host holds
        // count; one below the floor was never sent.
        func reportedDate(of kind: DeliveryTransitionLedger.Kind) -> Date? {
            guard let record = records.last(where: { $0.kind == kind && window.contains($0.date) }) else { return nil }
            return state.deliveryTransitions.entries.first { $0.sequenceNum == record.sequenceNum && $0.isReported }?.date
        }
        let hostAtDetection = hostLast(before: window.upperBound)
        var finalDose: UnfinalizedDose?
        if pending.observed == .suspend {
            if let date = reportedDate(of: .suspend) {
                finalDose = UnfinalizedDose(suspendStartTime: date)
            } else if let hostAtDetection, hostAtDetection.kind == .suspend, window.contains(hostAtDetection.date) {
                finalDose = UnfinalizedDose(suspendStartTime: hostAtDetection.date)
            } else {
                logger.warning("Pump history has no record of the suspend seen at \(pending.detectedAt); reporting it there")
                let dose = UnfinalizedDose(suspendStartTime: pending.detectedAt)
                events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate))
                recordReportedTransition(.suspend, at: dose.startDate, earliest: window.lowerBound, latest: window.upperBound)
                finalDose = dose
            }
        } else if let date = reportedDate(of: .resume) {
            finalDose = UnfinalizedDose(resumeStartTime: date, insulinType: state.insulinType)
        } else if let hostAtDetection, hostAtDetection.kind == .suspend {
            logger.warning("Pump history has no record of the resume seen at \(pending.detectedAt); reporting it at \(pending.lastConfirmed)")
            let date = max(pending.lastConfirmed, hostAtDetection.date.addingTimeInterval(1))
            let dose = UnfinalizedDose(resumeStartTime: date, insulinType: state.insulinType)
            events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate))
            recordReportedTransition(.resume, at: date, earliest: window.lowerBound, latest: window.upperBound)
            finalDose = dose
        } else if let tempBasalEnd {
            let dose = scheduledBasal(from: tempBasalEnd)
            events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))
            finalDose = dose
        }

        logger.info("Pump history dated the \(pending.observed) seen at \(pending.detectedAt): \(events.count) event(s)")
        finish(pending, finalDose: finalDose, events: events)
    }

    // MARK: - Building the batch

    private func finishedTempBasal(_ dose: UnfinalizedDose, at end: Date) -> NewPumpEvent {
        let entry = dose.toDoseEntry(isMutable: false, endDate: max(end, dose.startDate), now: now)
        return NewPumpEvent.tempBasal(dose: entry, date: entry.startDate)
    }

    private func scheduledBasal(from date: Date) -> UnfinalizedDose {
        UnfinalizedDose(
            basalRate: getScheduledBasalRate(at: date.addingTimeInterval(state.pumpClockOffset)),
            insulinType: state.insulinType,
            startDate: date
        )
    }

    /// A batch that finishes the temp basal the host holds open replaces pending events, as the
    /// live path's do, so it carries whatever is still running.
    private func finish(
        _ pending: DeliveryTransitionLedger.PendingTransition,
        finalDose: UnfinalizedDose?,
        events: [NewPumpEvent]
    ) {
        state.deliveryTransitions.pending = nil
        if let finalDose, isPlaceholder(for: pending) {
            state.basalDose = finalDose
        }

        var events = events.sorted { $0.date < $1.date }
        let finishesTempBasal = events.contains { $0.dose?.type == .tempBasal }
        if finishesTempBasal {
            events += getActivePumpEvents()
        }
        if !events.isEmpty {
            emitPumpEvents(events, replacePendingEvents: finishesTempBasal)
        }
        notifyDelegateStateUpdated()
    }
}
