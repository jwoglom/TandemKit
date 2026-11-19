import Foundation
import LoopKit

/// Suspends, resumes and temp basal ends the pump made on its own, dated from its history log
/// rather than from the reading that noticed them (#333, #331).
///
/// Neither host revises one once told: Trio keeps a row per (timestamp, type), and Loop never
/// counts a non-bolus dose older than its last finished basal (#354). So the first report must
/// carry the pump's date, and must reach the host before anything the app commands after it.
/// Behind `historyBackfill` a change is left pending for the next history pass; a sync that saw it
/// waits for that pass, and an app command reports it first. An app suspend or resume waits the
/// same way, so it reaches the host under its record's identity. Without the flag, or without the
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
        if observed == .basal {
            state.deliveryTransitions.interruptedTemp = nil
        }

        let held = state.basalDose
        if Self.isSameDelivery(observed, as: held.type) {
            state.deliveryTransitions.lastConfirmedObservation = now
            return false
        }
        if observed == .tempBasal, held.type == .resume, let resumed = resumedTempBasal(after: held.startDate) {
            state.deliveryTransitions.lastConfirmedObservation = now
            state.basalDose = resumed
            state.lastReconciliation = now
            notifyDelegateStateUpdated()
            emitPumpEvents([NewPumpEvent.tempBasal(dose: resumed.toDoseEntry(isMutable: true, now: now), of: resumed)])
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

    /// A temp the pump runs in place of the one the host holds: one whose set the app lost the
    /// answer to, or one set on the pump. History ends the held temp and adopts the pump's.
    func observeReplacedTempBasal(_ status: CurrentBasalStatusResponse) {
        let held = state.basalDose
        guard status.basalType == .tempBasal, held.type == .tempBasal, state.deliveryTransitions.pending == nil,
              datesTransitionsFromHistory
        else {
            return
        }
        guard let temp = bluetooth.write(TempRateRequest()) else {
            logger.warning("No temp rate status; taking the temp basal the pump runs as the one reported")
            return
        }
        guard temp.active else { return }
        // The pump stamped the start on the clock in force then, which a set since (a DST change) has
        // moved: a temp begun before a set back reads ahead of the phone, or less ahead than it ran.
        let stamped = hostDate(forPumpDate: temp.startTime)
        let onClockBefore = state.lastPumpClockStep
            .flatMap { $0.foundAt > held.startDate ? stamped.addingTimeInterval($0.by) : nil }
        let latest = now.addingTimeInterval(Self.transitionMatchTolerance)
        if stamped > latest {
            logger.warning("The pump dates the temp basal it runs at \(stamped), ahead of the phone; its clock went back since")
        }
        let starts = [stamped, onClockBefore].compactMap { $0 }.filter { $0 <= latest }
        let otherPercent = held.tempPercent.map { $0 != temp.percentage } ?? false
        // A held temp cut at a segment change starts there, after the pump's record of its start.
        let heldStart = held.startDate.addingTimeInterval(Self.transitionMatchTolerance)
        guard otherPercent || !starts.isEmpty && !starts.contains(where: { $0 <= heldStart }) else {
            return
        }
        let start = starts.first ?? now

        logger.warning("The pump runs a \(temp.percentage)% temp basal from \(start) in place of the one reported at \(held.startDate); dating the change from pump history")
        let lastSeen = state.deliveryTransitions.lastConfirmedObservation ?? held.startDate
        state.deliveryTransitions.pending = PendingTransition(
            prior: held,
            observed: .tempBasal,
            detectedAt: now,
            lastConfirmed: max(held.startDate, min(lastSeen, start)),
            replacement: PendingTransition.ReplacingTemp(
                start: start,
                percent: temp.percentage,
                rate: roundToSupportedBasalRate(unitsPerHour: status.profileBasalRate * Double(temp.percentage) / 100)
            )
        )
        notifyDelegateStateUpdated()
    }

    /// A reading of a temp rate other than the one a stop interrupted: the pump did not resume it.
    func forgetInterruptedTempUnlessRunning(_ status: CurrentBasalStatusResponse) {
        guard status.basalType == .tempBasal, let interrupted = state.deliveryTransitions.interruptedTemp,
              let percent = interrupted.tempPercent
        else {
            return
        }
        if !Self.tempBasalReadbackMatches(status, percent: percent) {
            logger.info("The pump runs \(status.currentBasalRate) U/hr, not the \(percent)% temp basal its stop interrupted")
            state.deliveryTransitions.interruptedTemp = nil
        }
    }

    /// The rest of the temp a stop interrupted, which the pump runs again from a resume at
    /// `resumedAt` until its programmed end, under a `raw` of its own. Takes it.
    func resumedTempBasal(after resumedAt: Date) -> UnfinalizedDose? {
        guard let interrupted = state.deliveryTransitions.interruptedTemp else { return nil }
        state.deliveryTransitions.interruptedTemp = nil
        // Trio orders two rows in one second arbitrarily.
        let start = resumedAt.addingTimeInterval(1)
        guard start < interrupted.estimatedEndDate else { return nil }
        let running = splitAtSegmentChanges(interrupted, through: start).running
        logger.warning("The pump resumed the temp basal its stop interrupted; reporting it from \(start) to \(interrupted.estimatedEndDate)")
        return interrupted.tempBasalPart(rate: running.value, from: start, until: interrupted.estimatedEndDate)
    }

    /// The temp that replaced `pending.prior` from its start, at its percent of the pump's rate:
    /// the one read at detection, or the schedule's on the pump's clock across a segment change since.
    private func replacingDose(
        _ replacement: PendingTransition.ReplacingTemp,
        detectedAt: Date,
        start: Date,
        duration: TimeInterval,
        automatic: Bool,
        tempRateId: Int? = nil
    ) -> UnfinalizedDose {
        let crossedAChange = !pumpSegmentChanges(after: start, through: detectedAt).isEmpty
        let rate = crossedAChange
            ? roundToSupportedBasalRate(unitsPerHour: pumpScheduledBasalRate(at: start) * Double(replacement.percent) / 100)
            : replacement.rate
        return UnfinalizedDose(
            tempRate: rate,
            duration: duration,
            automatic: automatic,
            insulinType: state.insulinType,
            startDate: start,
            tempRateId: tempRateId,
            tempPercent: replacement.percent,
            eventRaw: tempBasalEventRaw(tempRateId: tempRateId)
        )
    }

    func historyTickFailed(startedAt: Date) {
        reconciliationLog.recordSkippedPass(startedAt: startedAt, reason: "Pump history could not be read", at: now)
        bluetooth.ensureConnected { _ in
            if let pending = self.state.deliveryTransitions.pending, startedAt >= pending.detectedAt {
                self.logger.warning("Pump history could not be read; reporting the \(pending.observed) seen at \(pending.detectedAt) at detection")
                self.reportTransition(pending)
            }
            if !self.isAwaitingHistory {
                self.releaseHistoryWaiters()
            }
        }
    }

    /// An app suspend or resume, left for the history pass as a pump-side change is, so it reaches
    /// the host under its pump record's identity. False without history to date it.
    func leaveCommandedTransitionForHistory(_ observed: DoseType, sentAt: Date) -> Bool {
        guard datesTransitionsFromHistory else { return false }
        let held = state.basalDose
        let pending = PendingTransition(prior: held, observed: observed, detectedAt: now, lastConfirmed: max(held.startDate, sentAt))
        state.deliveryTransitions.lastConfirmedObservation = now
        state.deliveryTransitions.pending = pending
        state.basalDose = placeholderDose(for: pending)
        notifyDelegateStateUpdated()
        return true
    }

    /// Once a history pass has reported a change the command left pending, or it is reported at
    /// detection after `transitionHistoryWait`.
    func completeOnceTransitionIsReported(_ completion: @escaping () -> Void) {
        guard state.deliveryTransitions.pending != nil else {
            completion()
            return
        }
        afterHistoryIsReported(completion)
        historyBackfillCoordinator.runTick()
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
        return UnfinalizedDose(basalRate: scheduledBasalRateInForce(), insulinType: state.insulinType, startDate: pending.detectedAt)
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

    /// A history pass's non-bolus reports, which go to the host as one batch, ascending.
    struct HistoryReportBatch {
        var events: [NewPumpEvent] = []
        /// It ends or re-states the temp basal the host holds as mutable, so it replaces.
        var replacesHeldTemp = false
    }

    func reportTransition(_ pending: PendingTransition, tempRateEnd: Date? = nil) {
        var batch = HistoryReportBatch()
        closeTransition(pending, tempRateEnd: tempRateEnd, into: &batch)
        emitHistoryReports(batch)
    }

    /// The temp that replaced a held one, from its `TempRateActivated`, and its end if it has one.
    struct AdoptedTemp {
        let dose: UnfinalizedDose
        let end: Date?
    }

    /// Adds what `pending` leaves unsaid after the batch's other reports. Without the pump's record
    /// each end is dated the way that counts more insulin.
    func closeTransition(
        _ pending: PendingTransition,
        tempRateEnd: Date? = nil,
        adopting adopted: AdoptedTemp? = nil,
        suspendedBy record: (raw: Data, sequenceNum: UInt32)? = nil,
        into batch: inout HistoryReportBatch
    ) {
        let prior = pending.prior
        let tolerance = Self.transitionMatchTolerance
        let earliest = pending.lastConfirmed.addingTimeInterval(-tolerance)
        let latest = pending.detectedAt.addingTimeInterval(tolerance)
        var events: [NewPumpEvent] = []

        var tempBasalEnd: Date?
        if prior.type == .tempBasal {
            let lastSeen = splitAtSegmentChanges(prior, through: pending.lastConfirmed).running
            // Against the schedule the host counts after it, on the phone's clock.
            let end = tempRateEnd ?? adopted?.dose.startDate ?? pending.replacement?.start
                ?? (lastSeen.value < getScheduledBasalRate(at: lastSeen.startDate) ? pending.lastConfirmed : pending.detectedAt)
            let endDate = max(min(end, pending.detectedAt), prior.startDate)
            let (finished, last) = splitAtSegmentChanges(prior, through: endDate)
            let entry = last.toDoseEntry(isMutable: false, endDate: max(endDate, last.startDate), now: now)
            events += finished
            events.append(NewPumpEvent.tempBasal(dose: entry, of: last))
            tempBasalEnd = entry.endDate
            if pending.observed == .suspend {
                state.deliveryTransitions.interruptedTemp = last
            }
            // Loop keeps the mutable row it holds over a non-replacing report with the same raw.
            batch.replacesHeldTemp = true
        }

        if let replacement = pending.replacement {
            let final = closeReplacement(replacement, of: pending, adopted: adopted, after: tempBasalEnd, into: &events)
            logger.info("Reporting the temp basal that replaced the one reported at \(prior.startDate): \(events.count) event(s)")
            state.deliveryTransitions.pending = nil
            state.basalDose = final
            state.lastReconciliation = now
            batch.events += events
            return
        }
        var final: UnfinalizedDose
        switch (pending.observed == .suspend, hostTransition(before: .distantFuture)) {
        case let (true, host?) where host.kind == .suspend:
            final = UnfinalizedDose(suspendStartTime: host.date)
        case (true, _):
            final = UnfinalizedDose(suspendStartTime: pending.detectedAt)
            events.append(NewPumpEvent.suspend(dose: final.toDoseEntry(), date: final.startDate, record: record?.raw))
            recordReportedTransition(.suspend, at: final.startDate, earliest: earliest, latest: latest, sequenceNum: record?.sequenceNum)
        case let (false, host?) where host.kind == .suspend:
            final = UnfinalizedDose(resumeStartTime: max(pending.lastConfirmed, host.date.addingTimeInterval(1)), insulinType: state.insulinType)
            events.append(NewPumpEvent.resume(dose: final.toDoseEntry(), date: final.startDate))
            recordReportedTransition(.resume, at: final.startDate, earliest: earliest, latest: latest)
        case let (false, host?) where host.kind == .resume && host.date > prior.startDate:
            final = UnfinalizedDose(resumeStartTime: host.date, insulinType: state.insulinType)
        default:
            let start = tempBasalEnd ?? pending.detectedAt
            final = UnfinalizedDose(basalRate: scheduledBasalRateInForce(at: start), insulinType: state.insulinType, startDate: start)
            events.append(NewPumpEvent.basal(dose: final.toDoseEntry(), date: final.startDate))
        }
        if final.type == .resume, pending.observed == .tempBasal, let resumed = resumedTempBasal(after: final.startDate) {
            events.append(NewPumpEvent.tempBasal(dose: resumed.toDoseEntry(isMutable: true, now: now), of: resumed))
            final = resumed
            batch.replacesHeldTemp = true
        }

        logger.info("Reporting the \(pending.observed) seen at \(pending.detectedAt): \(events.count) event(s)")
        state.deliveryTransitions.pending = nil
        state.basalDose = final
        state.lastReconciliation = now
        batch.events += events
    }

    /// The temp the pump runs after `pending.prior`. From history it is held as reported, until its
    /// completion; at detection its duration is unknown, so it is reported finished at the reading
    /// that counts more insulin, and the scheduled basal after it.
    private func closeReplacement(
        _ replacement: PendingTransition.ReplacingTemp,
        of pending: PendingTransition,
        adopted: AdoptedTemp?,
        after priorEnd: Date?,
        into events: inout [NewPumpEvent]
    ) -> UnfinalizedDose {
        let end: Date?
        let dose: UnfinalizedDose
        if let adopted {
            dose = adopted.dose
            end = adopted.end
        } else {
            // Never after detection, or the dose would end before it starts: a pending change saved by a
            // build that took a start ahead of the phone still carries it.
            let start = min(max(replacement.start, priorEnd ?? replacement.start), pending.detectedAt)
            dose = replacingDose(replacement, detectedAt: pending.detectedAt, start: start, duration: now.timeIntervalSince(start), automatic: false)
            let lastSeen = max(pending.detectedAt, state.deliveryTransitions.lastConfirmedObservation ?? pending.detectedAt)
            end = dose.value > getScheduledBasalRate(at: dose.startDate) ? lastSeen : pending.detectedAt
        }

        guard let end else {
            let (finished, running) = splitAtSegmentChanges(dose, through: now)
            events += finished
            events.append(NewPumpEvent.tempBasal(dose: running.toDoseEntry(isMutable: true, now: now), of: running))
            return running
        }
        let (finished, last) = splitAtSegmentChanges(dose, through: end)
        let entry = last.toDoseEntry(isMutable: false, endDate: max(end, last.startDate), now: now)
        events += finished
        events.append(NewPumpEvent.tempBasal(dose: entry, of: last))
        let scheduled = UnfinalizedDose(basalRate: scheduledBasalRateInForce(at: entry.endDate), insulinType: state.insulinType, startDate: entry.endDate)
        // Seen by a command's own reading, the command reports in this second; Trio orders two rows in one arbitrarily.
        if now.timeIntervalSince(entry.endDate) >= 1 {
            events.append(NewPumpEvent.basal(dose: scheduled.toDoseEntry(), date: scheduled.startDate))
        }
        return scheduled
    }

    func emitHistoryReports(_ batch: HistoryReportBatch) {
        var events = batch.events
        if batch.replacesHeldTemp {
            let reported = Set(events.map(\.raw))
            events += getActivePumpEvents().filter { !reported.contains($0.raw) }
        }
        events.sort { $0.date < $1.date }
        if !events.isEmpty {
            emitPumpEvents(events, replacePendingEvents: batch.replacesHeldTemp)
        }
        notifyDelegateStateUpdated()
        // A pass reports its boluses after this; `reportHistoryDoses` releases once it has.
        if !isAwaitingHistory, !awaitsHistoryBoluses {
            releaseHistoryWaiters()
        }
    }

    // MARK: - History pass

    private struct PumpTransition {
        let sequenceNum: UInt32
        let kind: DeliveryTransitionLedger.Kind
        let date: Date

        /// Every pump manager reports this record under it, so a host told by an earlier one keeps
        /// its row when a later one loads the same history.
        func raw(_ serial: HistoryLogSyncIdentifier.PumpSerial) -> Data {
            HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: sequenceNum)
        }
    }

    /// The pump's suspends and resumes the host was never given, at the pump's time, and a pending
    /// change resolved once the tick has read the log past it.
    func reportHistoryDeliveryTransitions(
        after outcome: HistoryBackfillCoordinator.TickOutcome,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial
    ) -> HistoryReportBatch {
        var batch = HistoryReportBatch()
        guard let pumpRange = outcome.pumpSequenceRange else { return batch }
        // From the pump's status, even when the read after it failed, so a change in the meantime counts.
        if !state.deliveryTransitions.isTracking(pumpSerial: serial.rawValue, lastSequenceNum: pumpRange.upperBound) {
            logger.info("Tracking delivery changes on pump \(serial.rawValue) after record \(pumpRange.upperBound)")
            state.deliveryTransitions.track(pumpSerial: serial.rawValue, after: pumpRange.upperBound)
        }
        guard state.deliveryTransitions.trackedAfter != nil else { return batch }
        guard let covered = outcome.reportableRange else {
            if let pending = state.deliveryTransitions.pending, outcome.startedAt >= pending.detectedAt {
                logger.warning("Pump history was not read; reporting the \(pending.observed) seen at \(pending.detectedAt) at detection")
                closeTransition(pending, into: &batch)
            }
            return batch
        }

        let dates: HistoryRecordDates
        do {
            dates = try historyRecordDates(historyLogStore.logs(pumpSerial: serial.rawValue, in: covered)
                .map { $0.parsed() }
                .sorted { $0.sequenceNum < $1.sequenceNum })
        } catch {
            logger.error("Could not read the history log store for delivery transitions: \(error)")
            return batch
        }
        let stored = dates.logs

        let now = self.now
        let floor = now.addingTimeInterval(-DeliveryTransitionLedger.retention)
        let tolerance = Self.transitionMatchTolerance
        state.deliveryTransitions.prune(before: floor)

        if let pending = state.deliveryTransitions.pending {
            guard outcome.startedAt >= pending.detectedAt else {
                logger.info("Waiting for a tick that started after the \(pending.observed) seen at \(pending.detectedAt)")
                return batch
            }
            let reachesBack = outcome.isDeepBackfillComplete || outcome.reachesPumpStart
                || stored.first.map { dates.phoneDate(of: $0) <= pending.lastConfirmed } == true
            guard outcome.readsThroughPumpEnd, reachesBack else {
                logger.warning("Pump history does not cover the \(pending.observed) seen at \(pending.detectedAt); reporting it at detection")
                closeTransition(pending, into: &batch)
                return batch
            }
        }

        var records: [PumpTransition] = []
        for log in stored {
            let kind: DeliveryTransitionLedger.Kind
            switch log {
            case is PumpingSuspendedHistoryLog:
                kind = .suspend
            case is PumpingResumedHistoryLog:
                kind = .resume
            default:
                continue
            }
            let date = dates.phoneDate(of: log)
            if state.deliveryTransitions.isTracked(sequenceNum: log.sequenceNum, date: date) {
                records.append(PumpTransition(sequenceNum: log.sequenceNum, kind: kind, date: date))
            }
        }
        records.removeAll { $0.date < floor || $0.date > now.addingTimeInterval(tolerance) }
        if let pending = state.deliveryTransitions.pending {
            datePendingRecord(of: pending, in: &records)
        }

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
                events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate, record: record.raw(serial)))
                recordReportedTransition(.suspend, at: record.date, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)

            case .resume:
                // Trio takes a resume with no suspend before it as suspended until the resume.
                guard let host = hostTransition(before: record.date), host.kind == .suspend else {
                    continue
                }
                let dose = UnfinalizedDose(resumeStartTime: max(record.date, host.date.addingTimeInterval(1)), insulinType: state.insulinType)
                events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate, record: record.raw(serial)))
                recordReportedTransition(.resume, at: dose.startDate, earliest: record.date, latest: record.date, sequenceNum: record.sequenceNum)
            }
        }

        if !events.isEmpty {
            logger.info("Reporting \(events.count) suspend/resume event(s) from pump history")
        }
        batch.events += events
        guard let pending = state.deliveryTransitions.pending else {
            return batch
        }

        if let replacement = pending.replacement {
            let activation = stored.last { log in
                guard let activated = log as? TempRateActivatedHistoryLog else { return false }
                return Int(activated.percent.rounded()) == replacement.percent
                    && abs(dates.phoneDate(of: activated).timeIntervalSince(replacement.start)) <= tolerance
            } as? TempRateActivatedHistoryLog
            if let activation, activation.tempRateId == pending.prior.tempRateId {
                logger.info("The temp basal the pump runs is the one reported at \(pending.prior.startDate)")
                state.deliveryTransitions.pending = nil
                return batch
            }
            let adopted = activation.map { activation in
                let dose = replacingDose(
                    replacement,
                    detectedAt: pending.detectedAt,
                    start: dates.phoneDate(of: activation),
                    duration: TimeInterval(activation.durationMilliseconds) / 1000,
                    automatic: stored.contains { ($0 as? SetTempRateResponseHistoryLog)?.tempRateId == activation.tempRateId }
                        && !isManualTempRate(activation.tempRateId),
                    tempRateId: activation.tempRateId
                )
                return AdoptedTemp(dose: dose, end: tempRateEnd(of: dose, in: stored, dates: dates))
            }
            if adopted == nil {
                logger.warning("Pump history has no record of the temp basal seen at \(pending.detectedAt); reporting it at detection")
            }
            closeTransition(pending, tempRateEnd: tempRateEnd(of: pending.prior, in: stored, dates: dates), adopting: adopted, into: &batch)
            return batch
        }

        let window = pending.lastConfirmed.addingTimeInterval(-tolerance) ... pending.detectedAt.addingTimeInterval(tolerance)
        let completedAt = tempRateEnd(of: pending.prior, in: stored, dates: dates)
        let end = completedAt.map { dateOfChange($0, in: pending) }
            ?? records.first { $0.kind == .suspend && $0.date > pending.prior.startDate && window.contains($0.date) }?.date
        // A suspension from before this manager watched the pump, as after a re-pair, is dated at detection
        // but keeps the identity of its record, which a manager that watched it reported it under.
        let suspension = stored.last { $0 is PumpingSuspendedHistoryLog || $0 is PumpingResumedHistoryLog } as? PumpingSuspendedHistoryLog
        closeTransition(
            pending,
            tempRateEnd: end,
            suspendedBy: suspension.map { (HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: $0.sequenceNum), $0.sequenceNum) },
            into: &batch
        )
        if completedAt != nil {
            state.deliveryTransitions.interruptedTemp = nil
        }
        return batch
    }

    private func datePendingRecord(of pending: PendingTransition, in records: inout [PumpTransition]) {
        let kind: DeliveryTransitionLedger.Kind
        if pending.observed == .suspend {
            kind = .suspend
        } else if pending.prior.type == .suspend {
            kind = .resume
        } else {
            return
        }
        guard let index = records.firstIndex(where: { $0.kind == kind && isInWindow($0.date, of: pending) }) else { return }
        let record = records[index]
        records[index] = PumpTransition(sequenceNum: record.sequenceNum, kind: record.kind, date: dateOfChange(record.date, in: pending))
    }

    /// A record is to the pump's second, up to a second before the change, which came after the last
    /// reading of the state before it (an app command's send) and by its detection. One outside that
    /// window is not the change's own and keeps its date.
    private func dateOfChange(_ date: Date, in pending: PendingTransition) -> Date {
        guard isInWindow(date, of: pending) else { return date }
        return min(max(date, pending.lastConfirmed), pending.detectedAt)
    }

    private func isInWindow(_ date: Date, of pending: PendingTransition) -> Bool {
        let tolerance = Self.transitionMatchTolerance
        return pending.lastConfirmed.addingTimeInterval(-tolerance) <= date && date <= pending.detectedAt.addingTimeInterval(tolerance)
    }

    /// The pump's `TempRateCompleted` for `dose`, on the phone's clock.
    func tempRateEnd(of dose: UnfinalizedDose, in logs: [HistoryLog], dates: HistoryRecordDates) -> Date? {
        guard dose.type == .tempBasal, let tempRateId = dose.tempRateId,
              let completed = logs.last(where: { ($0 as? TempRateCompletedHistoryLog)?.tempRateId == tempRateId }) as? TempRateCompletedHistoryLog
        else {
            return nil
        }
        let date = dates.phoneDate(of: completed)
        let scheduledEnd = dose.estimatedEndDate
        // One that ran out ran its whole programmed duration; its record is off that end only by clock error.
        let ranOut = completed.timeLeft == 0 && abs(date.timeIntervalSince(scheduledEnd)) <= Self.transitionMatchTolerance
        return ranOut ? scheduledEnd : date
    }
}
