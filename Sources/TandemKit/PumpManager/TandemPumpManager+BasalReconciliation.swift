import Foundation
import LoopKit

/// Compares the basal the pump delivered, from its history log, with what the host was told, and
/// logs each difference once.
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

    func reconcileBasalHistory(after outcome: HistoryBackfillCoordinator.TickOutcome, pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial) {
        guard let covered = outcome.sessionCovered else { return }
        let now = self.now
        state.reportedBasal.prune(now: now)
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

        let result = BasalReconciler.reconcile(
            timeline,
            against: state.reportedBasal,
            schedule: hostBasalSchedule,
            floor: floor,
            now: now,
            isExempt: isOverReportedNearASegmentChange
        )
        for difference in result.differences where loggedBasalDifferences.insert(difference.chunk.sequenceNum).inserted {
            logger.warning("Basal difference: \(describe(difference))")
        }
        for (day, residual) in result.residualByDay.sorted(by: { $0.key < $1.key }) {
            logger.info("Basal cycle residual for \(day): \(residual) U")
        }
        logger.info(
            "Basal reconciliation: \(result.matched) chunk(s) match, \(result.differences.count) differ, \(result.skipped) skipped"
        )
    }

    /// A temp worked out against the next segment's rate is reported at the request on purpose.
    func isOverReportedNearASegmentChange(_ chunk: PumpBasalTimeline.Chunk) -> Bool {
        chunk.kind == .temp && !pumpSegmentChanges(after: chunk.start, through: chunk.start.addingTimeInterval(Self.segmentChangeWindow)).isEmpty
    }

    private func describe(_ difference: BasalReconciler.Difference) -> String {
        let chunk = difference.chunk
        let action: String
        switch difference.host.source {
        case .schedule:
            action = "a correction over the schedule"
        case let .tempBasal(row) where row.isMutable:
            action = "ending or re-stating the held temp basal"
        case .tempBasal:
            action = "a correction over a finalized temp basal"
        case .suspended:
            action = "none; the transitions pass owns it"
        }
        let trust = chunk.isTrusted ? "" : ", untrusted so not corrected"
        return "279 #\(chunk.sequenceNum) \(chunk.start)-\(chunk.end): pump \(chunk.unitsPerHour) U/hr (\(chunk.kind)), "
            + "host \(difference.host.rate) U/hr; would take \(action)\(trust)"
    }
}
