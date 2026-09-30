import Foundation
import LoopKit

/// The diagnostics screen's layout and copied text, built here so it is tested on Linux. Leaves
/// out the pump serial and every `raw`, which embeds it, so the text can go into an issue.
struct HistoryBackfillReport {
    enum Tone: Equatable {
        case normal
        case warning
        case critical
    }

    struct Finding: Equatable, Identifiable {
        let id: Int
        let tone: Tone
        let message: String
    }

    struct Row: Equatable, Identifiable {
        let id: Int
        let label: String
        let value: String
        let detail: String?
        let tone: Tone
    }

    struct Section: Equatable, Identifiable {
        let title: String
        let footer: String?
        let rows: [Row]

        var id: String { title }
    }

    /// Past this, a pump bolus reported in flight is taken to have lost its completion (#452).
    static let inFlightWarningAge: TimeInterval = .minutes(30)
    /// Past this, an unfinalized app bolus nothing is tracking is flagged.
    static let orphanGrace: TimeInterval = .minutes(10)
    static let staleTickAge: TimeInterval = .minutes(15)
    /// Under Trio's SMBs these run to a hundred or more a day, and say little once finalized.
    static let listedFinalizedAppBoluses = 10
    static let clockOffsetWarning: TimeInterval = .minutes(1)

    let capturedAt: Date
    let findings: [Finding]
    let sections: [Section]
    private let format: Format

    init(_ snapshot: HistoryBackfillSnapshot, timeZone: TimeZone = .current) {
        let format = Format(now: snapshot.capturedAt, timeZone: timeZone)
        self.format = format
        capturedAt = snapshot.capturedAt
        findings = Self.findings(snapshot, format)
        sections = [
            Self.readPosition(snapshot, format),
            Self.liveDoses(snapshot, format),
            Self.resolutionCounts(snapshot, format),
            Self.recentResolutions(snapshot, format),
            Self.ledger(snapshot, format),
            Self.reportingPass(snapshot, format),
            Self.ticks(snapshot, format),
            Self.sessionStore(snapshot, format),
            Self.floors(snapshot, format),
            Self.flags(snapshot)
        ]
    }

    var capturedText: String {
        format.clock(capturedAt)
    }

    var text: String {
        var lines = [
            "TandemKit history backfill report",
            "Captured \(format.stamp(capturedAt))",
            "Contains dosing history. No pump serial or dose identifiers.",
            "",
            "Findings"
        ]
        lines += findings.isEmpty ? ["- None"] : findings.map { "- \(Self.marker($0.tone))\($0.message)" }
        for section in sections {
            lines += ["", section.title]
            for row in section.rows {
                lines.append("  \(Self.marker(row.tone))\(row.label): \(row.value)")
                if let detail = row.detail {
                    lines.append("      \(detail)")
                }
            }
            if let footer = section.footer {
                lines.append("  (\(footer))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func marker(_ tone: Tone) -> String {
        switch tone {
        case .normal: return ""
        case .warning: return "[!] "
        case .critical: return "[!!] "
        }
    }

    // MARK: - Findings

    private static func findings(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> [Finding] {
        var found: [(Tone, String)] = []
        let flags = snapshot.flags
        let monitor = snapshot.monitor

        if !flags.historyBackfill {
            found.append((.warning, "History Backfill is off: the pump's history log is never read, so nothing below changes."))
            if flags[.historyDoseReporting] {
                found.append((.warning, "History Dose Reporting is on but has no effect while History Backfill is off."))
            }
        } else if !flags.historyDoseReporting {
            found.append((.normal, "History Dose Reporting is off: boluses found in pump history are read but not reported to the app."))
        }

        if !snapshot.isPumpSerialKnown {
            found.append((.warning, "The pump serial isn't known yet, so history can't be stored or reported until a PumpVersion response arrives."))
        }
        if snapshot.bookkeepingMatchesPump == false {
            found.append((.warning, "The saved read position belongs to another pump. The next tick starts this one from scratch."))
        }

        if let watermark = snapshot.bookkeeping?.watermark, let status = monitor.lastStatus {
            if watermark > status.lastSequenceNum {
                found.append((
                    .critical,
                    "The watermark (\(watermark)) is past the pump's newest entry (\(status.lastSequenceNum)): the pump's log restarted. The next tick re-reads it from scratch."
                ))
            } else if watermark < status.lastSequenceNum {
                let behind = status.lastSequenceNum - watermark
                found.append((.normal, "\(behind) entr\(behind == 1 ? "y" : "ies") on the pump not read yet, as of \(format.clock(status.readAt))."))
            }
        }

        if flags.historyBackfill, snapshot.isPumpSerialKnown {
            if let last = monitor.lastCompletedTick {
                let age = snapshot.capturedAt.timeIntervalSince(last.finishedAt)
                if age > staleTickAge, monitor.runningTickStartedAt == nil {
                    found.append((.warning, "The last completed backfill tick was \(Format.duration(age)) ago. Syncs may not be running."))
                }
            } else if monitor.runningTickStartedAt == nil {
                found.append((.normal, "No backfill tick has completed since the app launched."))
            }
        }

        if let latest = monitor.recentTicks.first, latest.skipped == .noStatus {
            found.append((.warning, "The last tick got no history log status from the pump."))
        }

        if let outcome = monitor.lastCompletedTick?.outcome {
            if !outcome.rangesFailed.isEmpty {
                found.append((
                    .warning,
                    "\(outcome.rangesFailed.count) range(s) failed on the last tick: \(Format.ranges(outcome.rangesFailed)). They are read again on the next one."
                ))
            }
            if outcome.hitDeepSliceCap {
                found.append((
                    .warning,
                    "The walk backward hit its cap of \(HistoryBackfillPlanner.maxDeepSlicesPerTick) slices on the last tick. Repeated hits mean it is not converging, for example a pump clock far ahead."
                ))
            }
            if !outcome.isDeepBackfillComplete {
                found.append((.normal, "The walk backward has not yet reached \(format.date(snapshot.deepFetchTarget))."))
            }
        }

        if !snapshot.storeGaps.isEmpty {
            let missing = snapshot.storeGaps.reduce(0) { $0 + $1.count }
            found.append((
                .warning,
                "\(snapshot.storeGaps.count) gap(s), \(missing) entr\(missing == 1 ? "y" : "ies"), in what this session has read: \(Format.ranges(snapshot.storeGaps)). They are read again on the next tick."
            ))
        }

        if snapshot.isHistoryStreamBusy, monitor.runningTickStartedAt == nil {
            found.append((.normal, "Another reader, such as the History Log Viewer, holds the pump's history stream. Backfill ticks skip until it finishes."))
        }

        if let held = snapshot.heldBolus {
            let windowEnd = held.estimatedEndAt.addingTimeInterval(TandemPumpManager.bolusFinalizationWindow)
            let when = windowEnd > snapshot.capturedAt
                ? "If it still can't, it is finalized at \(Format.units(held.deliveredUnits)) after \(format.clock(windowEnd))."
                : "Its window ended \(format.relative(windowEnd)); the next sync finalizes it at \(Format.units(held.deliveredUnits))."
            found.append((.warning, "Bolus \(Format.bolusId(held.bolusId)) is held: the pump hasn't confirmed how much it delivered. \(when)"))
        }

        for entry in snapshot.ledger.entries where !entry.isFinalized {
            let age = snapshot.capturedAt.timeIntervalSince(entry.eventDate)
            switch entry.origin {
            case .commanded:
                let tracked = snapshot.activeBolus?.bolusId == entry.bolusId || snapshot.heldBolus?.bolusId == entry.bolusId
                if !tracked, age > orphanGrace {
                    let recovery = flags.historyDoseReporting
                        ? "only history dose reporting can finalize it."
                        : "and history dose reporting, which could finalize it, is off."
                    found.append((
                        .warning,
                        "App bolus \(Format.bolusId(entry.bolusId)) from \(format.clock(entry.eventDate)) is unfinalized and nothing is tracking it; \(recovery)"
                    ))
                }
            case .history:
                if age > inFlightWarningAge {
                    let consequence = flags.historyDoseReporting
                        ? "It isn't re-reported meanwhile (#452)."
                        : "History Dose Reporting is off, so it won't be finalized."
                    found.append((
                        .warning,
                        "Pump bolus \(Format.bolusId(entry.bolusId)) was reported in flight and no completion has been read in \(Format.duration(age)). \(consequence)"
                    ))
                }
            }
        }

        for event in snapshot.resolutions.events where event.kind == .pumpBolusFound
            && event.bolusSource == BolusDeliveryHistoryLog.BolusSource.bluetoothRemoteBolus.rawValue {
            found.append((
                .warning,
                "Bolus \(Format.bolusId(event.bolusId)) was programmed over Bluetooth but this app has no record of it: another app, or this app's bolus whose acknowledgement was lost (#327)."
            ))
        }

        let fallbacks = snapshot.resolutions.events.filter { $0.kind == .heldBolusFinalizedWithFallback }
        if !fallbacks.isEmpty {
            found.append((
                .warning,
                "\(fallbacks.count) bolus(es) in the last 24 h were finalized with a fallback because the pump never confirmed the volume (#464)."
            ))
        }
        let extended = snapshot.resolutions.events.filter { $0.kind == .extendedBolusNotReported }
        if !extended.isEmpty {
            found.append((
                .warning,
                "\(extended.count) extended bolus(es) in pump history in the last 24 h were not reported, so their insulin is missing from the app (#424)."
            ))
        }

        if case let .deferred(reason)? = monitor.lastReportingPass?.result {
            found.append((.warning, "The last reporting pass was deferred to the next tick: \(reason)"))
        }
        if monitor.lastReportingPass?.result == .storeUnreadable {
            found.append((.warning, "The last reporting pass could not read the history store."))
        }

        if abs(snapshot.pumpClockOffset) > clockOffsetWarning {
            found.append((
                .normal,
                "The pump's clock is \(Format.duration(abs(snapshot.pumpClockOffset))) \(snapshot.pumpClockOffset > 0 ? "ahead of" : "behind") the phone's. History dates are not corrected for it."
            ))
        }

        let binding = floorBinding(snapshot)
        if binding != .retention {
            found.append((
                .normal,
                "Reporting reaches back only to \(format.date(snapshot.emitFloor)), \(binding.text). Boluses before then are never reported from history."
            ))
        }

        return found.enumerated()
            .sorted { ($0.element.0.rank, $0.offset) < ($1.element.0.rank, $1.offset) }
            .enumerated()
            .map { Finding(id: $0.offset, tone: $0.element.element.0, message: $0.element.element.1) }
    }

    // MARK: - Sections

    private static func readPosition(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        let watermark = snapshot.bookkeeping?.watermark
        let status = snapshot.monitor.lastStatus

        rows.add(
            "Last read (watermark)",
            watermark.map(String.init) ?? "None yet",
            detail: watermark.map { _ in
                snapshot.watermarkEntry.map {
                    "pump time \(format.clock($0.pumpDate)) · stored \(format.date($0.receivedAt))"
                } ?? "not in this session's store"
            }
        )

        if let status {
            var detail: [String] = []
            if let watermark {
                if watermark > status.lastSequenceNum {
                    detail.append("the watermark is past it")
                } else {
                    let behind = status.lastSequenceNum - watermark
                    detail.append(behind == 0 ? "all read" : "\(behind) not read yet")
                }
            }
            if let entry = snapshot.newestPumpEntry {
                detail.append("pump time \(format.clock(entry.pumpDate))")
            }
            rows.add(
                "Pump's newest entry",
                String(status.lastSequenceNum),
                detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                tone: (watermark ?? 0) > status.lastSequenceNum ? .critical : .normal
            )
            rows.add(
                "Pump's log",
                "\(status.firstSequenceNum)–\(status.lastSequenceNum)",
                detail: "\(status.numEntries) entries · read \(format.date(status.readAt))"
            )
        } else {
            rows.add("Pump's log", "Not read this session", detail: "Read Pump History Status fetches it")
        }

        if let advance = snapshot.monitor.lastWatermarkAdvance {
            let step = advance.from.map { "\($0) → \(advance.to) (+\(advance.to > $0 ? advance.to - $0 : 0))" } ?? "none → \(advance.to)"
            rows.add("Last advanced", format.date(advance.at), detail: step)
        } else {
            rows.add("Last advanced", "Not this session")
        }

        let savedFor: String
        switch snapshot.bookkeepingMatchesPump {
        case true?: savedFor = "This pump"
        case false?: savedFor = "Another pump"
        case nil: savedFor = snapshot.bookkeeping == nil ? "Nothing saved yet" : "Unknown (no serial yet)"
        }
        rows.add("Read position saved for", savedFor, tone: snapshot.bookkeepingMatchesPump == false ? .warning : .normal)

        return Section(title: "Read Position", footer: "The watermark is the highest sequence number ever read from this pump; it survives a relaunch.", rows: rows.rows)
    }

    private static func liveDoses(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()

        let bolusState: String
        switch snapshot.bolusState {
        case .noBolus: bolusState = "None"
        case .initiating: bolusState = "Initiating"
        case .inProgress: bolusState = "In progress"
        case .canceling: bolusState = "Canceling"
        }
        rows.add("Bolus state", bolusState)

        if let bolus = snapshot.activeBolus {
            rows.add(
                "Active bolus",
                "\(Format.bolusId(bolus.bolusId)) · \(Format.units(bolus.programmedUnits))",
                detail: [
                    "programmed \(format.clock(bolus.programmedAt))",
                    bolus.deliveryStartedAt.map { "delivering from \(format.clock($0))" } ?? "delivery not seen yet",
                    "estimated end \(format.clock(bolus.estimatedEndAt))",
                    bolus.automatic ? "automatic" : "manual",
                    snapshot.hasBolusProgressReporter ? "progress reported" : "no progress reporter"
                ].joined(separator: " · ")
            )
        } else {
            rows.add("Active bolus", "None")
        }

        if let held = snapshot.heldBolus {
            let windowEnd = held.estimatedEndAt.addingTimeInterval(TandemPumpManager.bolusFinalizationWindow)
            rows.add(
                "Held for finalization",
                "\(Format.bolusId(held.bolusId)) · \(Format.units(held.programmedUnits))",
                detail: [
                    "programmed \(format.clock(held.programmedAt))",
                    "held \(format.date(held.estimatedEndAt))",
                    "fallback \(Format.units(held.deliveredUnits))",
                    windowEnd > snapshot.capturedAt ? "window ends \(format.date(windowEnd))" : "window ended \(format.relative(windowEnd))"
                ].joined(separator: " · "),
                tone: .warning
            )
        } else {
            rows.add("Held for finalization", "None")
        }

        let basal = snapshot.basal
        var basalDetail = ["since \(format.date(basal.startedAt))"]
        let basalValue: String
        switch basal.type {
        case .basal:
            basalValue = "Scheduled \(Format.rate(basal.rate))"
        case .tempBasal:
            basalValue = "Temp basal \(Format.rate(basal.rate))"
            basalDetail.append("until \(format.clock(basal.estimatedEndAt))")
            if let tempRateId = basal.tempRateId {
                basalDetail.append("temp rate \(tempRateId)")
            }
        case .suspend:
            basalValue = "Suspended"
        case .resume:
            basalValue = "Resumed"
        case .bolus:
            basalValue = "Bolus"
        }
        rows.add("Basal", basalValue, detail: basalDetail.joined(separator: " · "))

        rows.add("Last reconciliation", snapshot.lastReconciliation.map(format.date) ?? "Never")
        rows.add("Pump clock offset", Format.signedDuration(snapshot.pumpClockOffset), detail: "positive when the pump is ahead of the phone")

        return Section(title: "Live Doses", footer: nil, rows: rows.rows)
    }

    private static func resolutionCounts(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        for kind in BolusResolutionLog.Kind.allCases {
            let count = snapshot.resolutions.count(kind)
            let flagged = count > 0 && (kind == .heldBolusFinalizedWithFallback || kind == .extendedBolusNotReported)
            rows.add(kind.title, String(count), tone: flagged ? .warning : .normal)
        }
        return Section(
            title: "Dose Resolutions",
            footer: "Counted since \(format.date(snapshot.resolutions.countingSince)). Only boluses the live path could not settle on its own; a bolus it finalizes itself is not counted.",
            rows: rows.rows
        )
    }

    private static func recentResolutions(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        for event in snapshot.resolutions.events.reversed() {
            var detail = [format.date(event.date)]
            if let doseDate = event.doseDate {
                var dated = "dated \(format.clock(doseDate))"
                if event.kind == .pumpBolusFound {
                    dated += ", found \(Format.duration(max(0, event.date.timeIntervalSince(doseDate)))) later"
                }
                detail.append(dated)
            }
            if let programmed = event.programmedUnits {
                detail.append("programmed \(Format.units(programmed))")
            }
            if event.isMutable {
                detail.append("reported mutable")
            } else if let delivered = event.deliveredUnits {
                detail.append("delivered \(Format.units(delivered))")
            }
            if let fallback = event.fallbackUnits, event.kind != .heldBolusFinalizedWithFallback {
                detail.append("fallback \(Format.units(fallback))")
            }
            if let source = Format.source(event.bolusSource) {
                detail.append(source)
            }
            if event.automatic == true {
                detail.append("automatic")
            }
            if let note = event.note {
                detail.append(note)
            }
            rows.add(
                event.kind.title,
                Format.bolusId(event.bolusId),
                detail: detail.joined(separator: " · "),
                tone: event.kind == .heldBolusFinalizedWithFallback || event.kind == .extendedBolusNotReported ? .warning : .normal
            )
        }
        if rows.rows.isEmpty {
            rows.add("None", "in the last 24 h")
        }
        return Section(title: "Recent Resolutions", footer: "Newest first, kept for 24 h.", rows: rows.rows)
    }

    private static func ledger(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        let entries = snapshot.ledger.entries
        let app = entries.filter { $0.origin == .commanded }
        let pump = entries.filter { $0.origin == .history }
        rows.add(
            "Entries",
            String(entries.count),
            detail: "\(app.count) app (\(app.filter(\.isFinalized).count) finalized) · \(pump.count) from pump history (\(pump.filter { !$0.isFinalized }.count) in flight)"
        )

        var finalizedAppShown = 0
        for entry in entries.sorted(by: { $0.eventDate > $1.eventDate }) {
            if entry.origin == .commanded, entry.isFinalized {
                guard finalizedAppShown < listedFinalizedAppBoluses else {
                    continue
                }
                finalizedAppShown += 1
            }
            let events = snapshot.resolutions.events.filter { $0.bolusId == entry.bolusId }
            let found = events.first { $0.kind == .pumpBolusFound }
            let settledBy = events.last { $0.kind.finalizes }

            let age = snapshot.capturedAt.timeIntervalSince(entry.eventDate)
            let status: String
            var tone = Tone.normal
            if entry.isFinalized {
                status = "Finalized"
            } else if snapshot.activeBolus?.bolusId == entry.bolusId, entry.origin == .commanded {
                status = "Delivering"
            } else if snapshot.heldBolus?.bolusId == entry.bolusId, entry.origin == .commanded {
                status = "Held"
                tone = .warning
            } else if entry.origin == .history {
                status = "In flight"
                tone = age > inFlightWarningAge ? .warning : .normal
            } else {
                status = "Unfinalized"
                tone = age > orphanGrace ? .warning : .normal
            }

            var detail = ["dated \(format.date(entry.eventDate))"]
            if let found {
                detail.append("found \(format.clock(found.date)), \(Format.duration(max(0, found.date.timeIntervalSince(entry.eventDate)))) later")
                if let programmed = found.programmedUnits {
                    detail.append(Format.units(programmed))
                }
                if let source = Format.source(found.bolusSource) {
                    detail.append(source)
                }
            }
            if entry.automatic {
                detail.append("automatic")
            }
            if entry.isFinalized {
                detail.append(settledBy.map { "via \($0.kind.title.lowercased())" } ?? (entry.origin == .commanded ? "by the live path" : "from history"))
            }

            rows.add(
                "\(Format.bolusId(entry.bolusId)) · \(entry.origin == .commanded ? "app" : "pump")",
                status,
                detail: detail.joined(separator: " · "),
                tone: tone
            )
        }

        return Section(
            title: "Bolus Report Ledger",
            footer: "Every bolus reported to the app in the last 24 h, by pump bolus ID, so history doesn't report an app bolus a second time (#344). Lists every pump bolus and every unfinalized one, but only the \(listedFinalizedAppBoluses) latest finalized app boluses. Tracking since \(format.date(snapshot.ledger.trackingSince)).",
            rows: rows.rows
        )
    }

    private static func reportingPass(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        guard let pass = snapshot.monitor.lastReportingPass else {
            rows.add(
                "Last pass",
                "None this session",
                detail: snapshot.flags.historyDoseReporting ? "runs after each tick that read something" : "History Dose Reporting is off"
            )
            return Section(title: "History Dose Reporting", footer: nil, rows: rows.rows)
        }

        let result: String
        var tone = Tone.normal
        switch pass.result {
        case .completed:
            result = "Completed"
        case let .deferred(reason):
            result = "Deferred: \(reason)"
            tone = .warning
        case .storeUnreadable:
            result = "Couldn't read the history store"
            tone = .warning
        }
        rows.add("Last pass", format.date(pass.date), detail: "\(result) · window \(Format.range(pass.covered)) · floor \(format.date(pass.floor))", tone: tone)
        rows.add("Bolus doses in the window", String(pass.boluses))
        rows.add("Reported", String(pass.reported))
        rows.add("Already finalized", String(pass.alreadyFinalized))
        rows.add("Awaiting completion (#452)", String(pass.awaitingCompletion))
        rows.add("Left to the live path", String(pass.leftToLivePath))
        rows.add("Before the reporting floor", String(pass.belowFloor))
        rows.add("Extended, not reported (#424)", String(pass.extendedBoluses), tone: pass.extendedBoluses > 0 ? .warning : .normal)

        return Section(title: "History Dose Reporting", footer: "What the last pass did with each bolus it mapped from this session's history.", rows: rows.rows)
    }

    private static func ticks(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        let monitor = snapshot.monitor
        let totals = monitor.totals

        rows.add("Now", monitor.runningTickStartedAt.map { "Running since \(format.clock($0))" } ?? "Idle")

        let skipped = totals.ticksSkipped.values.reduce(0, +)
        rows.add(
            "This session",
            "\(totals.ticksCompleted) completed · \(skipped) skipped",
            detail: [
                "since \(format.date(monitor.startedAt))",
                "\(totals.entriesRead) entries read",
                "\(totals.rangesFailed) failed ranges",
                "\(totals.watermarkResets) log restarts",
                "\(totals.deepSliceCapHits) slice-cap hits"
            ].joined(separator: " · ")
        )
        if skipped > 0 {
            let reasons = totals.ticksSkipped
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.text) \($0.value)" }
            rows.add("Skipped", String(skipped), detail: reasons.joined(separator: " · "))
        }

        for tick in monitor.recentTicks {
            if let reason = tick.skipped {
                rows.add(format.clock(tick.startedAt), "Skipped", detail: reason.text, tone: reason == .noStatus ? .warning : .normal)
                continue
            }
            guard let outcome = tick.outcome else {
                continue
            }
            let read = outcome.rangesRead.reduce(0) { $0 + $1.count }
            var detail = ["took \(Format.duration(tick.finishedAt.timeIntervalSince(tick.startedAt)))"]
            if !outcome.rangesRead.isEmpty {
                detail.append("read \(Format.ranges(outcome.rangesRead))")
            }
            if !outcome.rangesFailed.isEmpty {
                detail.append("failed \(Format.ranges(outcome.rangesFailed))")
            }
            if outcome.watermarkWasReset {
                detail.append("log restarted below \(outcome.watermarkBefore.map(String.init) ?? "?")")
            }
            let before = outcome.watermarkWasReset ? nil : outcome.watermarkBefore
            if let after = outcome.bookkeeping.watermark, after != before {
                detail.append("watermark \(before.map(String.init) ?? "none") → \(after)")
            }
            if let status = outcome.pumpStatus {
                detail.append("pump \(status.firstSequenceNum)–\(status.lastSequenceNum)")
            }
            detail.append(outcome.isDeepBackfillComplete ? "walk complete" : "walk continuing")
            if outcome.hitDeepSliceCap {
                detail.append("hit the slice cap")
            }
            rows.add(
                format.clock(tick.startedAt),
                read == 0 ? "Nothing new" : "Read \(read)",
                detail: detail.joined(separator: " · "),
                tone: outcome.rangesFailed.isEmpty && !outcome.hitDeepSliceCap ? .normal : .warning
            )
        }

        return Section(title: "Backfill Ticks", footer: "Newest first; the last \(HistoryBackfillMonitor.recentTickLimit) this session.", rows: rows.rows)
    }

    private static func sessionStore(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        if let covered = snapshot.monitor.sessionCovered {
            let span = [snapshot.sessionOldestEntry, snapshot.sessionNewestEntry]
                .map { $0.map { format.clock($0.pumpDate) } ?? "?" }
                .joined(separator: " → ")
            rows.add("Read this session", Format.range(covered), detail: "pump time \(span)")
        } else {
            rows.add("Read this session", "Nothing yet")
        }
        rows.add("Stored for this pump", String(snapshot.storedEntryCount), detail: "includes anything the History Log Viewer read")
        rows.add(
            "Gaps",
            snapshot.storeGaps.isEmpty ? "None" : String(snapshot.storeGaps.count),
            detail: snapshot.storeGaps.isEmpty ? nil : Format.ranges(snapshot.storeGaps),
            tone: snapshot.storeGaps.isEmpty ? .normal : .warning
        )
        rows.add("Pruned below", snapshot.prunedBelow.map(String.init) ?? "Nothing pruned")

        let walk: String
        switch snapshot.monitor.lastCompletedTick?.outcome?.isDeepBackfillComplete {
        case true?: walk = "Complete"
        case false?: walk = "In progress"
        case nil: walk = "Not started"
        }
        rows.add(
            "Walk backward",
            walk,
            detail: "oldest read \(snapshot.sessionOldestEntry.map { format.date($0.pumpDate) } ?? "—") · target \(format.date(snapshot.deepFetchTarget))"
        )
        rows.add("History stream", snapshot.isHistoryStreamBusy ? "In use" : "Idle")

        return Section(
            title: "Session Store",
            footer: "History read since launch, in memory only (#232). A relaunch empties it and the next tick reads the recent window again.",
            rows: rows.rows
        )
    }

    private static func floors(_ snapshot: HistoryBackfillSnapshot, _ format: Format) -> Section {
        var rows = Rows()
        rows.add(
            "First seen",
            snapshot.bookkeeping?.firstSeenFloor.map(format.date) ?? "Not yet",
            detail: "the deepest the walk reads; set when this pump was first seen and never moved"
        )
        rows.add(
            "Walk target",
            format.date(snapshot.deepFetchTarget),
            detail: "the later of \(Format.duration(HistoryBackfillPlanner.deepFetchLookback)) ago and first seen"
        )
        rows.add("Ledger tracking since", format.date(snapshot.ledger.trackingSince))
        rows.add("Reporting floor", format.date(snapshot.emitFloor), detail: "set by \(floorBinding(snapshot).text)")
        return Section(title: "Floors", footer: "Neither floor uses the host's filter date (#345).", rows: rows.rows)
    }

    private static func flags(_ snapshot: HistoryBackfillSnapshot) -> Section {
        var rows = Rows()
        let flags = snapshot.flags
        for flag in [TandemFeatureFlags.Flag.historyBackfill, .historyDoseReporting] {
            var detail = flags.isOverridden(flag) ? "changed from the default" : "default"
            if flag == .historyDoseReporting, flags[flag], !flags.historyBackfill {
                detail += " · no effect while History Backfill is off"
            }
            rows.add(flag.title, flags[flag] ? "On" : "Off", detail: detail)
        }
        return Section(title: "Feature Flags", footer: nil, rows: rows.rows)
    }

    // MARK: - Helpers

    private enum FloorBinding {
        case firstSeen
        case ledgerTracking
        case retention

        var text: String {
            switch self {
            case .firstSeen: return "when this pump was first seen"
            case .ledgerTracking: return "when the ledger started tracking"
            case .retention: return "the ledger's 24 h retention"
            }
        }
    }

    private static func floorBinding(_ snapshot: HistoryBackfillSnapshot) -> FloorBinding {
        if let firstSeen = snapshot.bookkeeping?.firstSeenFloor, firstSeen == snapshot.emitFloor {
            return .firstSeen
        }
        return snapshot.ledger.trackingSince == snapshot.emitFloor ? .ledgerTracking : .retention
    }

    private struct Rows {
        private(set) var rows: [Row] = []

        mutating func add(_ label: String, _ value: String, detail: String? = nil, tone: Tone = .normal) {
            rows.append(Row(id: rows.count, label: label, value: value, detail: detail, tone: tone))
        }
    }

    struct Format {
        let now: Date
        private let calendar: Calendar
        private let timeOnly: DateFormatter
        private let dayAndTime: DateFormatter
        private let full: DateFormatter

        init(now: Date, timeZone: TimeZone) {
            self.now = now
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            self.calendar = calendar
            timeOnly = Self.formatter("HH:mm:ss", timeZone)
            dayAndTime = Self.formatter("MMM d HH:mm:ss", timeZone)
            full = Self.formatter("yyyy-MM-dd HH:mm:ss ZZZZZ", timeZone)
        }

        private static func formatter(_ pattern: String, _ timeZone: TimeZone) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return formatter
        }

        /// The time, with the day when it isn't today.
        func clock(_ date: Date) -> String {
            calendar.isDate(date, inSameDayAs: now) ? timeOnly.string(from: date) : dayAndTime.string(from: date)
        }

        func date(_ date: Date) -> String {
            if date == .distantPast {
                return "the beginning"
            }
            return "\(clock(date)) (\(relative(date)))"
        }

        func stamp(_ date: Date) -> String {
            full.string(from: date)
        }

        func relative(_ date: Date) -> String {
            let delta = now.timeIntervalSince(date)
            guard abs(delta) >= 1 else {
                return "now"
            }
            return delta > 0 ? "\(Self.duration(delta)) ago" : "in \(Self.duration(-delta))"
        }

        static func duration(_ interval: TimeInterval) -> String {
            let seconds = Int(interval.rounded())
            guard seconds >= 1 else {
                return "<1s"
            }
            guard seconds >= 60 else {
                return "\(seconds)s"
            }
            let minutes = seconds / 60
            guard minutes >= 60 else {
                return seconds % 60 == 0 ? "\(minutes)m" : "\(minutes)m \(seconds % 60)s"
            }
            let hours = minutes / 60
            guard hours >= 24 else {
                return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
            }
            return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
        }

        static func signedDuration(_ interval: TimeInterval) -> String {
            let magnitude = abs(interval).rounded()
            guard magnitude >= 1 else {
                return "0s"
            }
            return (interval > 0 ? "+" : "-") + duration(magnitude)
        }

        /// Two decimals, the bolus increment; a third only when the pump reported one.
        static func units(_ units: Double) -> String {
            var text = String(format: "%.3f", units)
            if text.hasSuffix("0") {
                text.removeLast()
            }
            return "\(text) U"
        }

        static func rate(_ unitsPerHour: Double) -> String {
            String(format: "%.2f U/h", unitsPerHour)
        }

        static func bolusId(_ bolusId: Int?) -> String {
            bolusId.map { "#\($0)" } ?? "#?"
        }

        static func range(_ range: ClosedRange<UInt32>) -> String {
            range.lowerBound == range.upperBound
                ? "\(range.lowerBound)"
                : "\(range.lowerBound)–\(range.upperBound) (\(range.count))"
        }

        static func ranges(_ ranges: [ClosedRange<UInt32>], limit: Int = 4) -> String {
            let shown = ranges.prefix(limit).map(range).joined(separator: ", ")
            return ranges.count > limit ? "\(shown) and \(ranges.count - limit) more" : shown
        }

        static func source(_ bolusSource: Int?) -> String? {
            guard let bolusSource else {
                return nil
            }
            switch BolusDeliveryHistoryLog.BolusSource(rawValue: bolusSource) {
            case .quickBolus?: return "quick bolus button"
            case .gui?: return "pump UI"
            case .controlIQAutoBolus?: return "Control-IQ"
            case .bluetoothRemoteBolus?: return "Bluetooth remote"
            case nil: return "source \(bolusSource)"
            }
        }
    }
}

extension HistoryBackfillReport.Tone {
    /// Findings are listed most severe first.
    var rank: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .normal: return 2
        }
    }
}

extension BolusResolutionLog.Kind {
    var title: String {
        switch self {
        case .pumpBolusFound: return "Pump bolus found in history"
        case .pumpBolusFinalized: return "Pump bolus finalized"
        case .appBolusFinalizedFromHistory: return "App bolus finalized from history"
        case .bolusHeld: return "Bolus held, volume unconfirmed"
        case .heldBolusConfirmedByPump: return "Held bolus confirmed by the pump"
        case .heldBolusFinalizedFromHistory: return "Held bolus finalized from history"
        case .heldBolusFinalizedWithFallback: return "Held bolus finalized with fallback"
        case .extendedBolusNotReported: return "Extended bolus not reported"
        }
    }

    /// Whether this is the report that finalized the bolus.
    var finalizes: Bool {
        switch self {
        case .pumpBolusFinalized, .appBolusFinalizedFromHistory, .heldBolusConfirmedByPump,
             .heldBolusFinalizedFromHistory, .heldBolusFinalizedWithFallback:
            return true
        case .pumpBolusFound, .bolusHeld, .extendedBolusNotReported:
            return false
        }
    }
}

extension HistoryBackfillMonitor.SkipReason {
    var text: String {
        switch self {
        case .flagOff: return "History Backfill is off"
        case .noPumpSerial: return "no pump serial yet"
        case .queuedBehindRunningTick: return "a tick was running; runs after it"
        case .readerBusy: return "another history reader was active"
        case .noStatus: return "no history log status"
        }
    }
}
