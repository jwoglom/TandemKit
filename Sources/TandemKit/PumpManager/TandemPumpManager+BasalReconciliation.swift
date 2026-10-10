import Foundation
import LoopKit

/// Compares the basal the pump delivered, from its history log, with what the host was told, and
/// with `basalHistoryReporting` reports the difference: a correction where the host counts its
/// schedule, the end or a re-statement of the temp basal it holds.
///
/// Corrections go out in order, closed chunks only, so they lag the pump by 5 to 10 minutes. A
/// chunk waits behind an open one, a store gap younger than `basalGapPatience` passes, or a
/// pending delivery change: neither host counts a non-bolus dose reported out of order.
extension TandemPumpManager {
    static let basalHistoryTypes = [
        BasalDeliveryHistoryLog.typeId,
        DailyBasalHistoryLog.typeId,
        TempRateActivatedHistoryLog.typeId,
        TempRateCompletedHistoryLog.typeId,
        SetTempRateResponseHistoryLog.typeId,
        PumpingSuspendedHistoryLog.typeId,
        PumpingResumedHistoryLog.typeId,
        ControlIQPcmChangeHistoryLog.typeId,
        BolusActivatedHistoryLog.typeId,
        TimeChangedHistoryLog.typeId,
        DateChangeHistoryLog.typeId
    ]

    /// Read before the floor, so the cross-check knows a temp or suspend already in force there.
    static let basalHistoryLookback: TimeInterval = .hours(12)

    /// History passes a store gap holds reconciliation back before it is skipped.
    static let basalGapPatience = 2

    /// Whether a sync waits for the next history pass before it completes. Not for a Control-IQ end
    /// past the reporting horizon, which nothing could correct any more.
    var isAwaitingHistory: Bool {
        state.deliveryTransitions.pending != nil || (isHandingBackFromControlIQ && state.featureFlags.basalHistoryReporting)
    }

    /// Whether a sync waits for its history pass before it completes, as the pump may deliver boluses
    /// only history reports: Control-IQ's, or the quick bolus button's while it is not read as off.
    var awaitsHistoryBoluses: Bool {
        let possible = state.useControlIQ || isHandingBackFromControlIQ || state.quickBolusEnabled != false
        return possible && state.featureFlags.historyDoseReporting && historyLogStoreSerial != nil
    }

    private var isHandingBackFromControlIQ: Bool {
        state.controlIQEndedAt.map { now.timeIntervalSince($0) < BolusReportLedger.reportingHorizon } ?? false
    }

    func reconcileBasalHistory(
        after outcome: HistoryBackfillCoordinator.TickOutcome,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial,
        into batch: inout HistoryReportBatch
    ) {
        guard let covered = outcome.sessionCovered else { return }
        let now = self.now
        let reporting = state.featureFlags.basalHistoryReporting
        state.reportedBasal.prune(now: now)
        if let pumpRange = outcome.pumpSequenceRange,
           !state.reportedBasal.isTracking(pumpSerial: serial.rawValue, lastSequenceNum: pumpRange.upperBound)
        {
            logger.info("Reconciling basal on pump \(serial.rawValue) from its history's start")
            state.reportedBasal.track(pumpSerial: serial.rawValue, after: nil)
        }
        let floor = max(
            state.historyBackfill?.firstSeenFloor ?? .distantPast,
            now.addingTimeInterval(-BolusReportLedger.reportingHorizon)
        )

        let logs: [HistoryLog]
        let gaps: [ClosedRange<UInt32>]
        do {
            let since = Dates.fromInstantToJan12008EpochSeconds(floor.addingTimeInterval(state.pumpClockOffset - Self.basalHistoryLookback))
            logs = try historyLogStore.logs(
                pumpSerial: serial.rawValue,
                ofTypes: Self.basalHistoryTypes,
                sincePumpTimeSec: UInt32(clamping: Int64(max(0, since)))
            )
            .filter { covered.contains($0.sequenceNum) }
            .map { $0.parsed() }
            gaps = try logs.first.map { try historyLogStore.missingRanges(pumpSerial: serial.rawValue, in: $0.sequenceNum ... covered.upperBound) } ?? []
        } catch {
            logger.error("Could not read the history log store for basal reconciliation: \(error)")
            return
        }

        let dates = historyRecordDates(logs)
        let timeline = PumpBasalTimeline(
            logs: logs,
            date: dates.phoneDate(of:),
            gaps: gaps,
            readThrough: outcome.readsThroughPumpEnd ? outcome.startedAt : nil
        )
        if !timeline.problems.isEmpty {
            logger.warning("Pump basal history fails its checks; not correcting around: \(timeline.problems.joined(separator: "; "))")
        }

        // What the host counts once this pass's other reports reach it.
        let waitingGap = waitingStoreGap(gaps)
        let blockingOpen = timeline.openChunks.filter { open in
            !(gapsGivenUp.contains { $0.lowerBound > open.sequenceNum })
        }
        let stop = [waitingGap?.lowerBound, blockingOpen.first?.sequenceNum].compactMap { $0 }.min()

        var pass = BasalReportingPass(
            ledger: state.reportedBasal,
            logs: logs,
            dates: dates,
            timeline: timeline,
            stop: stop,
            serial: serial,
            floor: floor,
            now: now
        )
        pass.ledger.record(batch.events, replacePendingEvents: batch.replacesHeldTemp)

        var firstUnresolved: Date?
        var resolvedThrough: UInt32?
        var residualByDay: [Date: Double] = [:]
        let from = reporting ? state.reportedBasal.reconciledThrough : nil
        chunks: for chunk in timeline.chunks where from.map({ chunk.sequenceNum > $0 }) ?? true {
            if stop.map({ chunk.sequenceNum > $0 }) ?? false || chunk.end > now {
                firstUnresolved = chunk.start
                break
            }
            // Twice at most: once the held temp basal ends, the chunk is compared with what follows it.
            for _ in 0 ..< 2 {
                let verdict = BasalReconciler.verdict(
                    for: chunk,
                    against: pass.ledger,
                    schedule: hostBasalSchedule,
                    floor: floor,
                    now: now,
                    isExempt: isOverReportedNearASegmentChange
                )
                guard case let .differs(host) = verdict else {
                    if case let .matches(residual) = verdict {
                        residualByDay[Calendar.current.startOfDay(for: chunk.start), default: 0] += residual
                    }
                    break
                }
                let difference = BasalReconciler.Difference(chunk: chunk, host: host)
                if loggedBasalDifferences.insert(chunk.sequenceNum).inserted {
                    logger.warning("Basal difference: \(describe(difference, reporting: reporting))")
                }
                guard reporting, chunk.isTrusted else { break }

                switch act(on: difference, pass: &pass, batch: &batch) {
                case .done:
                    break
                case .again:
                    continue
                case .wait:
                    firstUnresolved = chunk.start
                    break chunks
                }
                break
            }
            resolvedThrough = chunk.sequenceNum
        }

        if reporting, let resolvedThrough {
            state.reportedBasal.reconcile(through: resolvedThrough)
        }
        for (day, residual) in residualByDay.sorted(by: { $0.key < $1.key }) {
            logger.info("Basal cycle residual for \(day): \(residual) U")
        }
        if pass.corrections > 0 {
            logger.info("Reporting \(pass.corrections) basal correction(s) from pump history")
        }

        if let endedAt = state.controlIQEndedAt, outcome.startedAt > endedAt, outcome.readsThroughPumpEnd,
           firstUnresolved.map({ $0 >= endedAt }) ?? true, !blockingOpen.contains(where: { $0.start < endedAt })
        {
            logger.info("Pump history is reconciled past the end of Control-IQ at \(endedAt)")
            state.controlIQEndedAt = nil
        }
        confirmControlIQState(from: logs)
    }

    // MARK: - Acting

    struct BasalReportingPass {
        var ledger: ReportedBasalLedger
        let logs: [HistoryLog]
        let dates: HistoryRecordDates
        let timeline: PumpBasalTimeline
        /// No chunk past this sequence number may be reported yet.
        let stop: UInt32?
        let serial: HistoryLogSyncIdentifier.PumpSerial
        let floor: Date
        let now: Date
        var corrections = 0

        mutating func add(_ events: [NewPumpEvent], to batch: inout HistoryReportBatch) {
            ledger.record(events, replacePendingEvents: false)
            batch.events += events
        }
    }

    enum BasalAction {
        case done
        /// Compare the chunk again: the held temp basal ended before it.
        case again
        /// Leave it, and everything after it, for a later pass.
        case wait
    }

    private func act(on difference: BasalReconciler.Difference, pass: inout BasalReportingPass, batch: inout HistoryReportBatch) -> BasalAction {
        let chunk = difference.chunk
        guard state.deliveryTransitions.pending == nil else {
            logger.info("Leaving the basal difference at \(chunk.start) until the pending delivery change is reported")
            return .wait
        }
        let held = state.basalDose.type == .tempBasal ? state.basalDose : nil

        switch difference.host.source {
        case .schedule:
            let start = correctionStart(for: chunk, ledger: pass.ledger)
            if let held, start > held.startDate {
                // Neither host may hear of a dose after a temp basal it still holds as running.
                guard endHeldTemp(held, pass: &pass, batch: &batch) else { return .wait }
                return .again
            }
            guard let correction = correction(for: chunk, from: start, pass: pass) else { return .done }
            pass.add([correction], to: &batch)
            pass.corrections += 1
            return .done

        case let .tempBasal(row) where row.isMutable:
            guard let held, row.date == held.startDate else {
                logger.error("The host holds a running temp basal from \(row.date) the driver does not; leaving the difference at \(chunk.start)")
                return .done
            }
            if endHeldTemp(held, pass: &pass, batch: &batch) {
                return .again
            }
            return restate(held, at: chunk, pass: &pass, batch: &batch) ? .done : .wait

        case let .tempBasal(row):
            return correctFinalized(row, from: chunk, pass: &pass, batch: &batch) ? .done : .wait

        case .suspended:
            return .done
        }
    }

    /// Ends `held` at its `TempRateCompleted`, if the pump's history has it.
    private func endHeldTemp(_ held: UnfinalizedDose, pass: inout BasalReportingPass, batch: inout HistoryReportBatch) -> Bool {
        guard let end = tempRateEnd(of: held, in: pass.logs, dates: pass.dates) else { return false }
        logger.info("Pump history ends the temp basal from \(held.startDate) at \(end)")
        let pending = PendingTransition(
            prior: held,
            observed: .basal,
            detectedAt: pass.now,
            lastConfirmed: max(held.startDate, state.deliveryTransitions.lastConfirmedObservation ?? held.startDate)
        )
        var ended = HistoryReportBatch()
        closeTransition(pending, tempRateEnd: end, into: &ended)
        pass.add(ended.events, to: &batch)
        batch.replacesHeldTemp = true
        return true
    }

    /// The pump runs `held` at another rate from `chunk`: the part before it finishes at the old
    /// rate, and the rest runs on, mutable, at the pump's, as at a segment change.
    private func restate(_ held: UnfinalizedDose, at chunk: PumpBasalTimeline.Chunk, pass: inout BasalReportingPass, batch: inout HistoryReportBatch) -> Bool {
        let start = correctionStart(for: chunk, ledger: pass.ledger)
        guard start < held.estimatedEndDate else {
            logger.info("The temp basal from \(held.startDate) has run out with no completion in pump history yet")
            return false
        }
        let (finished, running) = splitAtSegmentChanges(held, through: start)
        let entry = running.toDoseEntry(isMutable: false, endDate: start, now: pass.now)
        let continuation = UnfinalizedDose(
            tempRate: chunk.unitsPerHour,
            duration: held.estimatedEndDate.timeIntervalSince(start),
            automatic: held.automatic,
            insulinType: held.insulinType,
            startDate: start,
            tempRateId: held.tempRateId,
            tempPercent: held.tempPercent
        )
        logger.info("Pump history runs the temp basal from \(held.startDate) at \(chunk.unitsPerHour) U/hr from \(start)")
        state.basalDose = continuation
        pass.add(finished + [
            NewPumpEvent.tempBasal(dose: entry, date: entry.startDate),
            NewPumpEvent.tempBasal(dose: continuation.toDoseEntry(isMutable: true, now: pass.now), date: start)
        ], to: &batch)
        batch.replacesHeldTemp = true
        return true
    }

    /// The host never revises a finalized temp basal, but Trio's IOB cuts it at the next row and does
    /// not resume it, so from `chunk` through its end every chunk is reported in its place. Loop
    /// counts no basal older than its last finished one, and ignores them.
    private func correctFinalized(
        _ row: ReportedBasalLedger.Row,
        from chunk: PumpBasalTimeline.Chunk,
        pass: inout BasalReportingPass,
        batch: inout HistoryReportBatch
    ) -> Bool {
        let end = pass.ledger.rows.map(\.date).filter { chunk.start < $0 && $0 < row.end }.min() ?? row.end
        let span = pass.timeline.chunks.filter { $0.sequenceNum >= chunk.sequenceNum && $0.start < end }
        guard !pass.timeline.openChunks.contains(where: { $0.sequenceNum > chunk.sequenceNum && $0.start < end }),
              span.allSatisfy({ part in pass.stop.map { part.sequenceNum < $0 } ?? true }),
              (span.last?.end ?? .distantPast) >= end || pass.timeline.chunks.contains(where: { $0.start >= end })
        else {
            logger.info("Waiting for the pump's chunks through the end of the temp basal from \(row.date)")
            return false
        }
        guard span.allSatisfy(\.isTrusted) else {
            logger.warning("Not correcting the temp basal from \(row.date): its chunks fail the pump history's checks")
            return true
        }
        logger.info("Reporting the pump's basal over the finalized temp basal from \(row.date) to \(end)")
        for part in span {
            let start = max(correctionStart(for: part, ledger: pass.ledger), row.date.addingTimeInterval(1))
            guard let correction = correction(for: part, from: start, until: end, pass: pass) else { continue }
            pass.add([correction], to: &batch)
            pass.corrections += 1
        }
        return true
    }

    /// Never in the same second as a row the host holds, whose order against it Trio leaves open.
    private func correctionStart(for chunk: PumpBasalTimeline.Chunk, ledger: ReportedBasalLedger) -> Date {
        let second = { (date: Date) in date.timeIntervalSinceReferenceDate.rounded(.down) }
        return ledger.rows
            .filter { second($0.date) == second(chunk.start) }
            .map { $0.date.addingTimeInterval(1) }
            .reduce(chunk.start, max)
    }

    private func correction(
        for chunk: PumpBasalTimeline.Chunk,
        from start: Date,
        until limit: Date = .distantFuture,
        pass: BasalReportingPass
    ) -> NewPumpEvent? {
        let end = pass.ledger.rows.map(\.date).filter { start < $0 && $0 < chunk.end }.min().map { min($0, limit) } ?? min(chunk.end, limit)
        guard end > start else { return nil }

        if let limit = state.maxBasalLimitMilliunits, chunk.commandedRate > limit {
            logger.error("Basal correction at \(chunk.unitsPerHour) U/hr is above the pump's max basal; a host capping temp basals there drops it")
        }
        let isAlgorithm = chunk.kind == .algorithm
        let setByTheApp = chunk.tempRateId.map { id in
            pass.logs.contains { ($0 as? SetTempRateResponseHistoryLog).map { $0.tempRateId == id && id != 0 } ?? false }
        } ?? false
        let raw = HistoryLogSyncIdentifier.logSequence(pumpSerial: pass.serial, sequenceNum: chunk.sequenceNum)
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: start,
            endDate: end,
            value: chunk.unitsPerHour,
            unit: .unitsPerHour,
            deliveredUnits: TandemPumpCapabilities.roundToReportingResolution(chunk.unitsPerHour * end.timeIntervalSince(start) / .hours(1)),
            description: "Basal from pump record \(chunk.sequenceNum)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: state.insulinType,
            automatic: isAlgorithm || (chunk.kind == .temp && setByTheApp),
            isMutable: false,
            wasProgrammedByPumpUI: isAlgorithm || (chunk.kind == .temp && !setByTheApp)
        )
        let title = isAlgorithm
            ? String(localized: "Control-IQ Basal", comment: "Pump Event title for basal Control-IQ delivered, read from pump history")
            : String(localized: "Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        return NewPumpEvent(date: start, dose: dose, raw: raw, title: title, type: .tempBasal)
    }

    // MARK: - Gaps

    /// The first store gap still inside its patience; one past it is skipped, once, with a warning.
    private func waitingStoreGap(_ gaps: [ClosedRange<UInt32>]) -> ClosedRange<UInt32>? {
        var seen: [ClosedRange<UInt32>: Int] = [:]
        for gap in gaps {
            let passes = (basalGapPasses[gap] ?? 0) + 1
            seen[gap] = passes
            if passes == Self.basalGapPatience + 1 {
                logger.warning("Pump history \(gap.lowerBound)-\(gap.upperBound) is still missing; reconciling basal past it")
            }
        }
        basalGapPasses = seen
        return gaps.sorted { $0.lowerBound < $1.lowerBound }.first { (seen[$0] ?? 0) <= Self.basalGapPatience }
    }

    private var gapsGivenUp: [ClosedRange<UInt32>] {
        basalGapPasses.filter { $0.value > Self.basalGapPatience }.map(\.key)
    }

    // MARK: - Control-IQ

    /// The pump's own records say whether Control-IQ runs; when they disagree with `useControlIQ`,
    /// read its status now rather than at the next daily settings read.
    private func confirmControlIQState(from logs: [HistoryLog]) {
        let latestDelivery = logs.last { $0 is BasalDeliveryHistoryLog } as? BasalDeliveryHistoryLog
        let latestPcm = logs.last { $0 is ControlIQPcmChangeHistoryLog } as? ControlIQPcmChangeHistoryLog
        let algorithmRuns = latestDelivery.map { $0.commandedRateSourceEnum == .algorithm || $0.commandedRateSourceEnum == .tempRateAndAlgorithm } ?? false
        let pcmSaysOff = latestPcm?.currentPcmEnum == .openLoop
        guard algorithmRuns && !state.useControlIQ || pcmSaysOff && state.useControlIQ else { return }
        logger.info("Pump history disagrees with useControlIQ \(state.useControlIQ); reading Control-IQ status")
        fetchControlIQStatus()
    }

    // MARK: - Logging

    /// A temp worked out against the next segment's rate is reported at the request on purpose.
    func isOverReportedNearASegmentChange(_ chunk: PumpBasalTimeline.Chunk) -> Bool {
        chunk.kind == .temp && !pumpSegmentChanges(after: chunk.start, through: chunk.start.addingTimeInterval(Self.segmentChangeWindow)).isEmpty
    }

    private func describe(_ difference: BasalReconciler.Difference, reporting: Bool) -> String {
        let chunk = difference.chunk
        let action: String
        switch difference.host.source {
        case .schedule:
            action = "a correction over the schedule"
        case let .tempBasal(row) where row.isMutable:
            action = "ending or re-stating the held temp basal"
        case .tempBasal:
            action = "the pump's basal in place of a finalized temp basal"
        case .suspended:
            action = "none; the transitions pass owns it"
        }
        let outcome = !chunk.isTrusted ? "untrusted, so not corrected" : reporting ? "takes \(action)" : "would take \(action) with History Basal Reporting"
        return "279 #\(chunk.sequenceNum) \(chunk.start)-\(chunk.end): pump \(chunk.unitsPerHour) U/hr (\(chunk.kind)), "
            + "host \(difference.host.rate) U/hr; \(outcome)"
    }
}
