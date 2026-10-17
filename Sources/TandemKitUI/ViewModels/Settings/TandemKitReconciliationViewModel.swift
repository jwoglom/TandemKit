import Combine
import Foundation
import LoopKit

/// The Reconciliation debug screen: where the driver stands against the pump's history, what it
/// found that the app was not told, and the recent history passes, from `ReconciliationLog` and
/// the ledgers in `TandemPumpManagerState`.
final class TandemKitReconciliationViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        /// Right of the title.
        var value: String?
        /// Under the title.
        var detail: String?
        var isWarning = false
    }

    @Published private(set) var status: [Row] = []
    @Published private(set) var discrepancies: [Row] = []
    @Published private(set) var passes: [Row] = []
    @Published private(set) var differences: [Row] = []

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        refresh()
        pumpManager?.addStatusObserver(self, queue: .main)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    func refresh() {
        guard let pumpManager else { return }
        let now = pumpManager.now
        let state = pumpManager.state
        let log = pumpManager.reconciliationLog
        status = Self.statusRows(state: state, log: log, boundary: pumpManager.reconciliationBoundary, now: now)
        discrepancies = Self.discrepancyRows(state: state, log: log, now: now)
        passes = log.passes.reversed().map { Self.row(for: $0, now: now) }
        differences = log.differences.sorted { $0.start > $1.start }.map { Self.row(for: $0, now: now) }
    }

    // MARK: - Status

    private static func statusRows(state: TandemPumpManagerState, log: ReconciliationLog, boundary: Date?, now: Date) -> [Row] {
        var rows: [Row] = []

        var reconciled = Row(
            id: "reconciled",
            title: String(localized: "Last reconciled", comment: "Reconciliation screen: when the driver last accounted for the pump's delivery"),
            value: state.lastReconciliation.map { when($0, now: now) }
                ?? String(localized: "Never", comment: "Reconciliation screen: the pump's delivery has never been reconciled"),
            isWarning: state.lastReconciliation == nil
        )
        if let boundary, let last = state.lastReconciliation, last.timeIntervalSince(boundary) >= 1 {
            reconciled.detail = String(
                localized: "The app is given \(when(boundary, now: now)) until history reports the pump bolus that started then.",
                comment: "Reconciliation screen: the boundary handed to the app is held behind a pump bolus"
            )
            reconciled.isWarning = true
        }
        rows.append(reconciled)

        var history = Row(
            id: "history",
            title: String(localized: "Pump history", comment: "Reconciliation screen: how far the pump's history log has been read"),
            value: (state.historyBackfill?.watermark).map {
                String(localized: "Read to record #\($0)", comment: "Reconciliation screen: the last history record read")
            } ?? String(localized: "Not read", comment: "Reconciliation screen: no pump history has been read")
        )
        var details: [String] = []
        if let through = state.reportedBasal.reconciledThrough {
            details.append(String(localized: "Basal reconciled through record #\(through).", comment: "Reconciliation screen: the last basal record reconciled"))
        }
        if let last = log.passes.last, last.skipped == nil, !last.readsThroughPumpEnd {
            details.append(String(localized: "The last pass stopped short of the pump's newest record.", comment: "Reconciliation screen: the last history pass did not read to the end"))
        }
        history.detail = details.isEmpty ? nil : details.joined(separator: " ")
        rows.append(history)

        rows.append(Row(
            id: "pass",
            title: String(localized: "Last history pass", comment: "Reconciliation screen: when history was last compared"),
            value: log.passes.last.map { when($0.finishedAt, now: now) }
                ?? String(localized: "None yet", comment: "Reconciliation screen: no history pass has run"),
            isWarning: log.passes.last?.skipped != nil
        ))

        rows.append(clockRow(state: state))
        rows.append(profileRow(state: state, now: now))

        let flags = state.featureFlags
        rows.append(Row(
            id: "flags",
            title: String(localized: "Reporting", comment: "Reconciliation screen: which history reporting flags are on"),
            value: String(
                localized: "Backfill \(onOff(flags.historyBackfill)), boluses \(onOff(flags.historyDoseReporting)), basal \(onOff(flags.basalHistoryReporting))",
                comment: "Reconciliation screen: the state of the history backfill, bolus reporting and basal reporting flags"
            ),
            isWarning: !flags.historyBackfill
        ))

        if let today = log.residualDays.last {
            rows.append(Row(
                id: "residual",
                title: String(localized: "Cycle timing today", comment: "Reconciliation screen: the basal residual from the pump's 5-minute cycles"),
                value: String(
                    localized: "\(signedUnits(today.net)) over ^[\(today.cycles) cycle](inflect: true)",
                    comment: "Reconciliation screen: net residual and the number of matched cycles"
                ),
                detail: String(
                    localized: "What the app counts less what the pump delivered over cycles whose rates matched: the app counts a change from its command, the pump from its next cycle. Not corrected.",
                    comment: "Reconciliation screen: what the cycle timing residual is"
                )
            ))
        }
        return rows
    }

    private static func clockRow(state: TandemPumpManagerState) -> Row {
        let title = String(localized: "Pump clock", comment: "Reconciliation screen: the pump's clock against the phone's")
        guard state.currentPumpTime != nil else {
            return Row(id: "clock", title: title, value: String(localized: "Not read", comment: "Reconciliation screen: the pump's clock has not been read"))
        }
        let offset = state.pumpClockOffset
        var value: String
        if abs(offset) < 1 {
            value = String(localized: "In step", comment: "Reconciliation screen: the pump's clock agrees with the phone's")
        } else if offset > 0 {
            value = String(localized: "\(duration(offset)) ahead", comment: "Reconciliation screen: the pump's clock runs ahead of the phone's")
        } else {
            value = String(localized: "\(duration(-offset)) behind", comment: "Reconciliation screen: the pump's clock runs behind the phone's")
        }
        if state.isPumpClockUntrusted {
            value = String(localized: "\(value), not trusted", comment: "Reconciliation screen: the pump's clock is too far off to dose on")
        } else if state.isPumpClockSkewed {
            value = String(localized: "\(value), skewed", comment: "Reconciliation screen: the pump's clock is off by more than the skew threshold")
        }
        return Row(id: "clock", title: title, value: value, isWarning: state.isPumpClockSkewed)
    }

    private static func profileRow(state: TandemPumpManagerState, now: Date) -> Row {
        let title = String(localized: "Basal profile", comment: "Reconciliation screen: the pump's basal profile against the app's schedule")
        if state.basalProfileUpdateFailed {
            return Row(
                id: "profile",
                title: title,
                value: String(localized: "Update failed", comment: "Reconciliation screen: writing the schedule to the pump failed"),
                detail: String(localized: "Temp basals are refused until the pump's profile reads back matching.", comment: "Reconciliation screen: consequence of a failed profile update"),
                isWarning: true
            )
        }
        if let since = state.basalRateMismatchDetectedAt {
            return Row(
                id: "profile",
                title: title,
                value: String(localized: "Syncing since \(when(since, now: now))", comment: "Reconciliation screen: the schedule is being written to the pump"),
                isWarning: true
            )
        }
        if !state.hasSyncedBasalRateSchedule {
            return Row(
                id: "profile",
                title: title,
                value: String(localized: "Not synced yet", comment: "Reconciliation screen: the app's schedule has not been written to the pump"),
                detail: String(localized: "Non-zero temp basals are refused until the pump's profile is known to match the app's schedule.", comment: "Reconciliation screen: consequence of an unsynced schedule"),
                isWarning: true
            )
        }
        return Row(id: "profile", title: title, value: String(localized: "Matches the app's schedule", comment: "Reconciliation screen: the pump's profile matches"))
    }

    // MARK: - Discrepancies

    private static func discrepancyRows(state: TandemPumpManagerState, log: ReconciliationLog, now: Date) -> [Row] {
        var rows: [Row] = []
        let transitions = state.deliveryTransitions

        if let pending = transitions.pending {
            if let replacement = pending.replacement {
                rows.append(Row(
                    id: "pending",
                    title: String(localized: "Temp basal replaced on the pump", comment: "Reconciliation screen: the pump runs a temp basal other than the one reported"),
                    detail: String(
                        localized: "The pump runs a \(replacement.percent)% temp basal from \(when(replacement.start, now: now)) in place of the one reported at \(when(pending.prior.startDate, now: now)). Waiting for pump history to date the change.",
                        comment: "Reconciliation screen: details of a replaced temp basal"
                    ),
                    isWarning: true
                ))
            } else {
                rows.append(Row(
                    id: "pending",
                    title: String(localized: "Delivery change awaiting pump history", comment: "Reconciliation screen: a suspend, resume or temp basal end the pump made on its own"),
                    detail: String(
                        localized: "The pump reports \(name(pending.observed)) where \(name(pending.prior.type)) was reported, seen \(when(pending.detectedAt, now: now)). Reported at detection if the next history pass does not date it.",
                        comment: "Reconciliation screen: details of a pending delivery change"
                    ),
                    isWarning: true
                ))
            }
        }

        if let interrupted = transitions.interruptedTemp {
            rows.append(Row(
                id: "interrupted",
                title: String(localized: "Temp basal interrupted by a pump stop", comment: "Reconciliation screen: a pump stop ended a temp basal the pump may resume"),
                detail: String(
                    localized: "\(rate(interrupted.value)) from \(when(interrupted.startDate, now: now)). If the pump resumes it before \(when(interrupted.estimatedEndDate, now: now)) the rest is reported then.",
                    comment: "Reconciliation screen: details of an interrupted temp basal"
                ),
                isWarning: true
            ))
        }

        for bolus in state.bolusReportLedger.unreported {
            rows.append(Row(
                id: "unreported-\(bolus.bolusId)",
                title: String(localized: "Pump bolus #\(bolus.bolusId) not yet reported", comment: "Reconciliation screen: a bolus the app did not start is waiting for history"),
                detail: String(
                    localized: "Seen running at \(when(bolus.startDate, now: now)). The app's boundary is held at \(when(bolus.holdsBoundaryAt, now: now)) until history reports it.",
                    comment: "Reconciliation screen: details of an unreported pump bolus"
                ),
                isWarning: true
            ))
        }

        if let bolus = state.bolusDose, bolus.isUnconfirmed {
            rows.append(Row(
                id: "unconfirmed",
                title: String(localized: "Bolus of \(units(bolus.value)) unconfirmed", comment: "Reconciliation screen: a bolus command the pump did not answer"),
                detail: String(
                    localized: "Sent \(when(bolus.startDate, now: now)); the pump has not said whether it started. Settled by the next bolus status read.",
                    comment: "Reconciliation screen: details of an unconfirmed bolus"
                ),
                isWarning: true
            ))
        }

        if let bolus = state.pendingBolusFinalization {
            rows.append(Row(
                id: "finalization",
                title: String(localized: "Bolus of \(units(bolus.value)) awaiting its delivered amount", comment: "Reconciliation screen: a bolus whose delivered volume could not be read"),
                detail: String(
                    localized: "Started \(when(bolus.startDate, now: now)); held at its programmed amount until the pump or its history gives the amount delivered.",
                    comment: "Reconciliation screen: details of a bolus awaiting finalization"
                ),
                isWarning: true
            ))
        }

        for part in state.bolusReportLedger.heldExtendedParts {
            rows.append(Row(
                id: "extended-\(part.bolusId)",
                title: String(localized: "Extended bolus #\(part.bolusId) running", comment: "Reconciliation screen: an extended bolus programmed off the app"),
                detail: String(
                    localized: "\(units(part.units ?? 0)) from \(when(part.eventDate, now: now)) to \(when(part.programmedEndDate ?? part.eventDate, now: now)), held open until history reads its completion.",
                    comment: "Reconciliation screen: details of a running extended bolus"
                )
            ))
        }

        if let excess = log.unreportedInsulinOnBoard {
            rows.append(Row(
                id: "iob",
                title: String(localized: "Pump holds \(units(excess)) of bolus insulin the app was not told of", comment: "Reconciliation screen: the pump's bolus IOB exceeds the boluses reported"),
                detail: String(
                    localized: "A bolus from the pump's screen or an extended bolus the app never heard of, or a report that was lost.",
                    comment: "Reconciliation screen: what unreported insulin on board means"
                ),
                isWarning: true
            ))
        }

        if let endedAt = state.controlIQEndedAt {
            rows.append(Row(
                id: "controliq",
                title: String(localized: "Control-IQ hand-back awaiting history", comment: "Reconciliation screen: Control-IQ was turned off and its basal is not reconciled yet"),
                detail: String(
                    localized: "Control-IQ ended \(when(endedAt, now: now)). Syncs wait for a history pass that reconciles past it.",
                    comment: "Reconciliation screen: details of the Control-IQ hand-back"
                ),
                isWarning: true
            ))
        }

        rows += differenceGroupRows(log.differences, now: now)

        for problem in log.problems.suffix(5).reversed() {
            rows.append(Row(
                id: "problem-\(problem.sequenceNum)",
                title: String(localized: "Pump record fails its cross-check", comment: "Reconciliation screen: a pump history record disagrees with the pump's other records"),
                detail: problem.description,
                isWarning: true
            ))
        }

        if let heldBack = log.passes.last?.basal?.heldBack, let detail = description(of: heldBack, now: now) {
            rows.append(Row(
                id: "heldback",
                title: String(localized: "Basal reconciliation held back", comment: "Reconciliation screen: the last pass left chunks for a later one"),
                detail: detail
            ))
        }
        return rows
    }

    private static func differenceGroupRows(_ differences: [ReconciliationLog.Difference], now: Date) -> [Row] {
        let open: [(ReconciliationLog.Outcome, String, String)] = [
            (
                .reportingOff,
                String(localized: "^[\(differences.count(of: .reportingOff)) basal cycle](inflect: true) differ, not corrected", comment: "Reconciliation screen: differences left because basal reporting is off"),
                String(localized: "History Basal Reporting is off.", comment: "Reconciliation screen: why differences are not corrected")
            ),
            (
                .untrusted,
                String(localized: "^[\(differences.count(of: .untrusted)) basal cycle](inflect: true) differ in records that fail their cross-check", comment: "Reconciliation screen: differences in untrusted records"),
                String(localized: "Not corrected: the pump's own records disagree about them.", comment: "Reconciliation screen: why untrusted differences are not corrected")
            ),
            (
                .waiting,
                String(localized: "^[\(differences.count(of: .waiting)) basal cycle](inflect: true) differ and wait for a later pass", comment: "Reconciliation screen: differences waiting"),
                String(localized: "Corrections go out in order, so these wait behind what comes before them.", comment: "Reconciliation screen: why differences wait")
            ),
            (
                .notCorrected,
                String(localized: "^[\(differences.count(of: .notCorrected)) basal cycle](inflect: true) differ with nothing to send", comment: "Reconciliation screen: differences acted on without a correction"),
                String(localized: "Nothing was left to correct, or the app holds a temp basal the driver does not.", comment: "Reconciliation screen: why a difference produced no correction")
            )
        ]
        return open.compactMap { outcome, title, reason in
            let group = differences.filter { $0.outcome == outcome }
            guard !group.isEmpty else { return nil }
            let net = group.reduce(0) { $0 + $1.units }
            let detail = String(
                localized: "\(reason) Over them the app counts \(signedUnits(net)) against the pump.",
                comment: "Reconciliation screen: a group of differences and the insulin the app counts over them"
            )
            return Row(id: "differences-\(outcome)", title: title, detail: detail, isWarning: true)
        }
    }

    private static func description(of heldBack: ReconciliationLog.Basal.HeldBack, now: Date) -> String? {
        switch heldBack {
        case let .storeGap(gap):
            return String(
                localized: "Records \(gap.lowerBound)–\(gap.upperBound) are missing from the session store. Nothing after them is corrected until they are read or given up.",
                comment: "Reconciliation screen: a store gap holds reconciliation back"
            )
        case let .heldTempBasal(start):
            return String(
                localized: "The temp basal from \(when(start, now: now)) has no completion in pump history yet.",
                comment: "Reconciliation screen: the held temp basal holds reconciliation back"
            )
        case let .finalizedTempBasal(start):
            return String(
                localized: "The cycles through the end of the temp basal from \(when(start, now: now)) are not all read yet.",
                comment: "Reconciliation screen: a finished temp basal's chunks hold reconciliation back"
            )
        case .openChunk, .pendingDeliveryChange:
            return nil
        }
    }

    // MARK: - Passes and differences

    private static func row(for pass: ReconciliationLog.Pass, now: Date) -> Row {
        let title = when(pass.startedAt, now: now)
        if let skipped = pass.skipped {
            return Row(
                id: "pass-\(pass.startedAt.timeIntervalSinceReferenceDate)",
                title: title,
                detail: String(localized: "Skipped: \(skipped)", comment: "Reconciliation screen: a history pass that could not run"),
                isWarning: true
            )
        }
        var parts: [String] = []
        if let covered = pass.covered {
            parts.append(pass.readsThroughPumpEnd
                ? String(localized: "Records \(covered.lowerBound)–\(covered.upperBound).", comment: "Reconciliation screen: the records a pass compared")
                : String(localized: "Records \(covered.lowerBound)–\(covered.upperBound), short of the pump's newest.", comment: "Reconciliation screen: the records a pass compared, not to the end"))
        } else {
            parts.append(String(localized: "Pump history not read.", comment: "Reconciliation screen: a pass whose tick did not read the log"))
        }
        if let basal = pass.basal {
            parts.append(String(
                localized: "^[\(basal.matched) cycle](inflect: true) matched, \(basal.differed) differ, \(basal.corrections) corrected.",
                comment: "Reconciliation screen: a pass's basal counts"
            ))
        }
        if pass.transitionsReported > 0 {
            parts.append(String(localized: "^[\(pass.transitionsReported) delivery change](inflect: true) reported.", comment: "Reconciliation screen: suspends, resumes and temp basal ends a pass reported"))
        }
        if pass.bolusesReported > 0 {
            parts.append(String(localized: "^[\(pass.bolusesReported) bolus](inflect: true) reported.", comment: "Reconciliation screen: boluses a pass reported"))
        }
        if let heldBack = pass.basal?.heldBack {
            parts.append(String(localized: "Held back by \(name(heldBack)).", comment: "Reconciliation screen: what stopped a pass short"))
        }
        return Row(id: "pass-\(pass.startedAt.timeIntervalSinceReferenceDate)", title: title, detail: parts.joined(separator: " "))
    }

    private static func row(for difference: ReconciliationLog.Difference, now: Date) -> Row {
        let isWarning: Bool
        let outcome: String
        switch difference.outcome {
        case .corrected:
            outcome = String(localized: "Corrected", comment: "Reconciliation screen: a basal difference was corrected")
            isWarning = false
        case .heldTempEnded:
            outcome = String(localized: "Ended the temp basal", comment: "Reconciliation screen: a basal difference ended the held temp basal")
            isWarning = false
        case .heldTempRestated:
            outcome = String(localized: "Re-stated the temp basal", comment: "Reconciliation screen: a basal difference re-stated the held temp basal")
            isWarning = false
        case .untrusted:
            outcome = String(localized: "Untrusted record", comment: "Reconciliation screen: a basal difference in a record that fails its cross-check")
            isWarning = true
        case .reportingOff:
            outcome = String(localized: "Reporting off", comment: "Reconciliation screen: a basal difference left because basal reporting is off")
            isWarning = true
        case .waiting:
            outcome = String(localized: "Waiting", comment: "Reconciliation screen: a basal difference left for a later pass")
            isWarning = true
        case .notCorrected:
            outcome = String(localized: "Not corrected", comment: "Reconciliation screen: a basal difference acted on with nothing to send")
            isWarning = true
        }
        return Row(
            id: "difference-\(difference.sequenceNum)",
            title: String(
                localized: "\(when(difference.start, now: now)) to \(time(difference.end))",
                comment: "Reconciliation screen: the span of a basal cycle that differs"
            ),
            value: outcome,
            detail: String(
                localized: "Pump: \(name(difference.pumpKind)) at \(rate(difference.pumpRate)). App: \(rate(difference.hostRate)) from its \(name(difference.hostSource)), \(signedUnits(difference.units)).",
                comment: "Reconciliation screen: what the pump delivered against what the app counts over one cycle"
            ),
            isWarning: isWarning
        )
    }

    // MARK: - Names

    private static func name(_ type: DoseType) -> String {
        switch type {
        case .suspend: String(localized: "a suspend", comment: "Reconciliation screen: a delivery state")
        case .resume: String(localized: "a resume", comment: "Reconciliation screen: a delivery state")
        case .tempBasal: String(localized: "a temp basal", comment: "Reconciliation screen: a delivery state")
        case .basal: String(localized: "the scheduled basal", comment: "Reconciliation screen: a delivery state")
        case .bolus: String(localized: "a bolus", comment: "Reconciliation screen: a delivery state")
        }
    }

    private static func name(_ kind: PumpBasalTimeline.Kind) -> String {
        switch kind {
        case .algorithm: "Control-IQ"
        case .temp: String(localized: "temp basal", comment: "Reconciliation screen: what the pump's record says it ran")
        case .profile: String(localized: "profile", comment: "Reconciliation screen: what the pump's record says it ran")
        case .suspended: String(localized: "suspended", comment: "Reconciliation screen: what the pump's record says it ran")
        }
    }

    private static func name(_ source: ReconciliationLog.HostSource) -> String {
        switch source {
        case .schedule: String(localized: "schedule", comment: "Reconciliation screen: where the app's rate comes from")
        case .heldTempBasal: String(localized: "running temp basal", comment: "Reconciliation screen: where the app's rate comes from")
        case .finalizedTempBasal: String(localized: "finished temp basal", comment: "Reconciliation screen: where the app's rate comes from")
        }
    }

    private static func name(_ heldBack: ReconciliationLog.Basal.HeldBack) -> String {
        switch heldBack {
        case let .storeGap(gap):
            String(localized: "missing records \(gap.lowerBound)–\(gap.upperBound)", comment: "Reconciliation screen: a store gap")
        case let .openChunk(sequenceNum):
            String(localized: "the open cycle at record #\(sequenceNum)", comment: "Reconciliation screen: a basal cycle not closed yet")
        case .pendingDeliveryChange:
            String(localized: "the pending delivery change", comment: "Reconciliation screen: a delivery change awaiting history")
        case .heldTempBasal:
            String(localized: "the running temp basal", comment: "Reconciliation screen: the temp basal the app holds")
        case .finalizedTempBasal:
            String(localized: "a finished temp basal's cycles", comment: "Reconciliation screen: a finished temp basal not fully read")
        }
    }

    // MARK: - Formatting

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter = RelativeDateTimeFormatter()

    /// The time alone on the phone's current day, else the date too.
    static func time(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? timeFormatter.string(from: date) : dateTimeFormatter.string(from: date)
    }

    /// The time and how long ago.
    static func when(_ date: Date, now: Date) -> String {
        String(
            localized: "\(time(date, now: now)) (\(relativeFormatter.localizedString(for: date, relativeTo: now)))",
            comment: "Reconciliation screen: a time and how long ago it was"
        )
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 {
            return String(localized: "\(seconds) s", comment: "Reconciliation screen: a duration in seconds")
        }
        if seconds < 3600 {
            return String(localized: "\(seconds / 60) min \(seconds % 60) s", comment: "Reconciliation screen: a duration in minutes and seconds")
        }
        return String(localized: "\(seconds / 3600) h \(seconds % 3600 / 60) min", comment: "Reconciliation screen: a duration in hours and minutes")
    }

    static func rate(_ unitsPerHour: Double) -> String {
        String(localized: "\(String(format: "%.2f", unitsPerHour)) U/hr", comment: "Reconciliation screen: a basal rate")
    }

    static func units(_ units: Double) -> String {
        String(localized: "\(String(format: "%.3f", units)) U", comment: "Reconciliation screen: an amount of insulin")
    }

    static func signedUnits(_ units: Double) -> String {
        String(localized: "\(String(format: "%+.3f", units)) U", comment: "Reconciliation screen: a signed amount of insulin")
    }

    private static func onOff(_ isOn: Bool) -> String {
        isOn
            ? String(localized: "on", comment: "Reconciliation screen: a flag that is on")
            : String(localized: "off", comment: "Reconciliation screen: a flag that is off")
    }
}

extension TandemKitReconciliationViewModel: PumpManagerStatusObserver {
    func pumpManager(_: any PumpManager, didUpdate _: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        DispatchQueue.main.async {
            self.refresh()
        }
    }
}

private extension [ReconciliationLog.Difference] {
    func count(of outcome: ReconciliationLog.Outcome) -> Int {
        filter { $0.outcome == outcome }.count
    }
}
