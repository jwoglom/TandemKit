import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The pump's own record of what it delivered, rebuilt from the emulator's history feed
/// (`GET /api/history`), the live `bolus` / `basal` / `last_bolus` / `alarms_history` snapshot
/// fields and the connection entries of `GET /api/log`. This is the side of the ledger a driver's
/// reports are diffed against (guide §11 "diff your reported timeline"; plan "PumpTimeline").
///
/// **Times.** Every instant here is a *true* instant on the pump's Clock, reconstructed from the
/// record's `pump_seconds` — what actually went on the wire — with the emulator's offsets removed:
///
///     unix = pump_seconds + 1_199_145_600 - wire_offset_seconds
///
/// `wire_offset_seconds` is the record's own: the offset the pump's clock was set to plus its
/// skew when the record was written, which for every record since the clock was last set is
/// `pump_timezone_offset_seconds + pump_offset_seconds`. Live snapshot fields use the clock's. The snapshot's
/// formatted `time` strings carry the same instants, but the wire seconds are what a driver
/// actually sees, so they stay the source.
struct PumpTimeline {
    // MARK: - Records

    /// pumpX2 `LastBolusStatusAbstractResponse.BolusStatus`, which is also what a
    /// `BolusCompleted` record's `completionStatusId` decodes as.
    enum BolusEndReason: Int {
        case stoppedUserTerminated = 0
        case stoppedAlarm = 1
        case stoppedMalfunction = 2
        case complete = 3
        case stoppedWireless = 4
        case rejectedWireless = 5
        case terminatedPLGS = 6
        /// The record carried no completion status at all.
        case unknown = -1
        /// A value outside the enum.
        case other = -2

        init(id: Int?) {
            guard let id else { self = .unknown; return }
            self = BolusEndReason(rawValue: id) ?? .other
        }

        /// True for every status that is the pump finishing what it was asked to deliver.
        var isCompletion: Bool { self == .complete }
    }

    struct Bolus: Equatable {
        let bolusId: Int
        let programmedUnits: Double?
        /// The pump-recorded start; nil when the emulator's history had no `BolusActivated` for it.
        let start: Date?
        let startPumpSeconds: Int?
        /// Set once the bolus ended (completed, stopped or aborted).
        let end: Date?
        let endPumpSeconds: Int?
        let deliveredUnits: Double?
        let endReason: BolusEndReason?
        /// pumpX2 `BolusDeliveryHistoryLog` source id: 8 is an app-commanded bolus. Not a field of
        /// `BolusActivated` on the wire, so the emulator reports it as `extra.bolusSourceId`.
        let sourceId: Int?
        var isFinished: Bool { end != nil }
    }

    struct TempRate: Equatable {
        let tempRateId: Int?
        let rate: Double?
        let percent: Int?
        let profileRate: Double?
        let start: Date
        let startPumpSeconds: Int
        /// `start + duration` as programmed; nil when the record carried no duration.
        let scheduledEnd: Date?
        /// When it actually ended (expiry, stop, replacement, or suspend); nil while running.
        let end: Date?
        let endPumpSeconds: Int?
        /// How much of the programmed duration was still to run when it ended, in seconds: zero for
        /// one that expired on its own, positive for one cut short (`TempRateCompleted.timeLeft`).
        let timeLeft: Int?
        var isFinished: Bool { end != nil }
        /// rate × actual (or scheduled) duration, what a finalized `deliveredUnits` should read.
        var deliveredUnits: Double? {
            guard let rate, let until = end ?? scheduledEnd else { return nil }
            return rate * until.timeIntervalSince(start) / .hours(1)
        }
    }

    struct Suspend: Equatable {
        /// The emulator's own word for it ("user", "occlusion", "alarm"), from `extra.reason`;
        /// falls back to the name of the wire's `reasonId` when the context is absent.
        let reason: String?
        /// pumpX2 `PumpingSuspendedHistoryLog.SuspendReason`: 0 user, 1 alarm, 2 malfunction.
        let reasonId: Int?
        let start: Date
        let startPumpSeconds: Int
        let resumed: Date?
        let resumedPumpSeconds: Int?
    }

    struct Alarm: Equatable {
        let alarmId: Int?
        /// The emulator's alert classification (`extra.alertTypeName`), e.g. "Occlusion".
        let alertType: String?
        /// Why the pump raised it (`extra.reason`), e.g. "occlusion".
        let reason: String?
        let message: String?
        let at: Date
        let pumpSeconds: Int
        /// When it stopped standing, from the matching `AlarmCleared` record or `alarms_history`.
        let cleared: Date?
        let clearedPumpSeconds: Int?
        var isCleared: Bool { cleared != nil }
    }

    struct Connection: Equatable {
        let connected: Bool
        let at: Date
    }

    /// Something in the history the builder could not place: an unknown type, or a record whose
    /// fields did not carry what it needed. Kept so a diff can say what it ignored.
    struct Unplaced: Equatable {
        let sequence: Int
        let type: String
        let note: String
    }

    let boluses: [Bolus]
    let tempRates: [TempRate]
    let suspends: [Suspend]
    let alarms: [Alarm]
    let connections: [Connection]
    let unplaced: [Unplaced]
    /// The history sequence range the timeline was built from.
    let historyRange: ClosedRange<Int>?

    // MARK: - Building

    /// Builds from the history feed and, optionally, the request log's connection entries. Records
    /// with a sequence at or below `afterSequence` are ignored, so a test can start from the
    /// history the emulator had before it began.
    ///
    /// `history` is `GET /api/history` rather than the snapshot's 50-record tail: a scenario that
    /// runs for a while loses records off the front of the tail without being told.
    static func build(
        snapshot: FaketandemSnapshot,
        history: [FaketandemHistoryEntry],
        log: [FaketandemLogEntry] = [],
        afterSequence: Int = 0
    ) -> PumpTimeline {
        let entries = history.filter { $0.sequence > afterSequence }.sorted { $0.sequence < $1.sequence }

        // Instants come from the wire seconds with the offsets removed, never from the formatted
        // `time` strings: the wire seconds are what a driver decodes, so reconstructing from them
        // is the same arithmetic the driver does and any disagreement is the emulator's, not a
        // rendering difference. A history record carries the offset it was written under, which
        // differs from the clock's for one written before the pump's clock was last set.
        let clock = snapshot.clock
        func instant(_ pumpSeconds: Int) -> Date { clock.instant(fromPumpSeconds: pumpSeconds) }
        func instant(_ entry: FaketandemHistoryEntry) -> Date { entry.instant(clock: clock) }

        var boluses: [Int: Bolus] = [:]
        var bolusOrder: [Int] = []
        var tempRates: [TempRate] = []
        var suspends: [Suspend] = []
        var alarms: [Alarm] = []
        var unplaced: [Unplaced] = []

        for entry in entries {
            let data = entry.data ?? [:]
            let extra = entry.extra ?? [:]
            switch entry.type {
            case "BolusActivated", "BolusRequestedMsg1":
                // Wire fields: bolusId, selectedIob, iob, bolusSize. The source rides on
                // BolusDeliveryHistoryLog, so the emulator reports it as context.
                guard let id = data["bolusId"]?.intValue else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no bolusId"))
                    continue
                }
                if boluses[id] != nil { continue } // BolusRequestedMsg1 after BolusActivated, or a repeat
                bolusOrder.append(id)
                boluses[id] = Bolus(
                    bolusId: id,
                    programmedUnits: data["bolusSize"]?.doubleValue,
                    start: instant(entry),
                    startPumpSeconds: entry.pumpSeconds,
                    end: nil,
                    endPumpSeconds: nil,
                    deliveredUnits: nil,
                    endReason: nil,
                    sourceId: extra["bolusSourceId"]?.intValue
                )

            case "BolusCompleted":
                // Wire fields: completionStatusId, bolusId, iob, insulinDelivered,
                // insulinRequested. completionStatusId IS the end reason — it decodes as the same
                // BolusStatus enum LastBolusStatus reports — and every path sets it.
                guard let id = data["bolusId"]?.intValue else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no bolusId"))
                    continue
                }
                let existing = boluses[id]
                if existing == nil { bolusOrder.append(id) }
                boluses[id] = Bolus(
                    bolusId: id,
                    programmedUnits: existing?.programmedUnits ?? data["insulinRequested"]?.doubleValue,
                    start: existing?.start,
                    startPumpSeconds: existing?.startPumpSeconds,
                    end: instant(entry),
                    endPumpSeconds: entry.pumpSeconds,
                    deliveredUnits: data["insulinDelivered"]?.doubleValue,
                    endReason: BolusEndReason(id: data["completionStatusId"]?.intValue),
                    sourceId: existing?.sourceId
                )

            case "TempRateActivated":
                // Wire fields: percent, durationMilliseconds, tempRateId. The absolute rates are
                // context: the record carries a percentage, and what it resolves to depends on the
                // profile the pump was running.
                let durationSeconds = extra["durationSeconds"]?.doubleValue
                    ?? data["durationMilliseconds"]?.doubleValue.map { $0 / 1000 }
                let profile = extra["normalRate"]?.doubleValue ?? snapshot.basal.profileRate
                let percent = data["percent"]?.intValue
                let rate = extra["tempRate"]?.doubleValue ?? percent.map { profile * Double($0) / 100 }
                let start = instant(entry)
                let scheduledEnd = extra["scheduledEndPumpSeconds"]?.intValue.map(instant)
                    ?? durationSeconds.map { start.addingTimeInterval($0) }
                tempRates.append(TempRate(
                    tempRateId: data["tempRateId"]?.intValue,
                    rate: rate,
                    percent: percent,
                    profileRate: profile,
                    start: start,
                    startPumpSeconds: entry.pumpSeconds,
                    scheduledEnd: scheduledEnd,
                    end: nil,
                    endPumpSeconds: nil,
                    timeLeft: nil
                ))

            case "TempRateCompleted":
                // Wire fields: tempRateId and timeLeft, and nothing else — so the id is what closes
                // the right temp rate, and the rate, start and delivered volume are context.
                let id = data["tempRateId"]?.intValue
                let byId = tempRates.lastIndex(where: { !$0.isFinished && (id == nil || $0.tempRateId == nil || $0.tempRateId == id) })
                guard let index = byId ?? tempRates.lastIndex(where: { !$0.isFinished }) else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no open temp rate to close"))
                    continue
                }
                let open = tempRates[index]
                tempRates[index] = TempRate(
                    tempRateId: open.tempRateId ?? id,
                    rate: open.rate ?? extra["tempRate"]?.doubleValue,
                    percent: open.percent ?? extra["percent"]?.intValue,
                    profileRate: open.profileRate ?? extra["normalRate"]?.doubleValue,
                    start: open.start,
                    startPumpSeconds: open.startPumpSeconds,
                    scheduledEnd: open.scheduledEnd,
                    end: instant(entry),
                    endPumpSeconds: entry.pumpSeconds,
                    timeLeft: data["timeLeft"]?.intValue
                )

            case "PumpingSuspended":
                // Wire fields: preSuspendState, insulinAmount, reasonId, rpaTimeout. The string the
                // emulator suspended for is context.
                let reasonId = data["reasonId"]?.intValue
                suspends.append(Suspend(
                    reason: extra["reason"]?.stringValue ?? reasonId.map(Self.suspendReasonName),
                    reasonId: reasonId,
                    start: instant(entry),
                    startPumpSeconds: entry.pumpSeconds,
                    resumed: nil,
                    resumedPumpSeconds: nil
                ))

            case "PumpingResumed":
                if let index = suspends.lastIndex(where: { $0.resumed == nil }) {
                    let open = suspends[index]
                    suspends[index] = Suspend(
                        reason: open.reason,
                        reasonId: open.reasonId,
                        start: open.start,
                        startPumpSeconds: open.startPumpSeconds,
                        resumed: instant(entry),
                        resumedPumpSeconds: entry.pumpSeconds
                    )
                } else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "resume without a suspend"))
                }

            case "AlarmActivated":
                // Wire fields: alarmId, faultLocatorData, param1, param2. The alert type, priority,
                // reason and message behind it are the emulator's own classification, so context.
                alarms.append(Alarm(
                    alarmId: data["alarmId"]?.intValue,
                    alertType: extra["alertTypeName"]?.stringValue,
                    reason: extra["reason"]?.stringValue,
                    message: extra["message"]?.stringValue,
                    at: instant(entry),
                    pumpSeconds: entry.pumpSeconds,
                    cleared: nil,
                    clearedPumpSeconds: nil
                ))

            case "AlarmCleared":
                // One record per alarm, carrying the alarmId of the AlarmActivated it closes.
                let id = data["alarmId"]?.intValue
                guard let index = alarms.lastIndex(where: { !$0.isCleared && (id == nil || $0.alarmId == id) }) else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "clear without a standing alarm"))
                    continue
                }
                let open = alarms[index]
                alarms[index] = Alarm(
                    alarmId: open.alarmId ?? id,
                    alertType: open.alertType ?? extra["alertTypeName"]?.stringValue,
                    reason: open.reason,
                    message: open.message ?? extra["message"]?.stringValue,
                    at: open.at,
                    pumpSeconds: open.pumpSeconds,
                    cleared: instant(entry),
                    clearedPumpSeconds: entry.pumpSeconds
                )

            default:
                unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "not a delivery record"))
            }
        }

        // `alarms_history` is the snapshot's record of every alarm that has been raised *and*
        // cleared, with both ends of the interval. It is the authority on the clearing instant —
        // the history log only has it if the AlarmCleared record fell inside this test's window —
        // so it fills in what the records above could not.
        for cleared in snapshot.alarmsHistory {
            guard let index = alarms.lastIndex(where: { $0.alarmId == cleared.id }) else { continue }
            let open = alarms[index]
            alarms[index] = Alarm(
                alarmId: open.alarmId,
                alertType: open.alertType ?? cleared.typeName,
                reason: open.reason,
                message: open.message ?? cleared.message,
                at: open.at,
                pumpSeconds: open.pumpSeconds,
                cleared: open.cleared ?? instant(cleared.clearedPumpSeconds),
                clearedPumpSeconds: open.clearedPumpSeconds ?? cleared.clearedPumpSeconds
            )
        }

        // The live snapshot enriches what history cannot: a running bolus's pump-side start and the
        // last bolus's end and delivered volume. It never adds a bolus on its own — both the
        // protocol and the harness paths write BolusActivated, and `last_bolus` may well be a bolus
        // from before `afterSequence`.
        if snapshot.bolus.active, let startSeconds = snapshot.bolus.startPumpSeconds, let existing = boluses[snapshot.bolus.bolusId] {
            boluses[snapshot.bolus.bolusId] = Bolus(
                bolusId: existing.bolusId,
                programmedUnits: existing.programmedUnits ?? snapshot.bolus.unitsTotal,
                start: existing.start ?? instant(startSeconds),
                startPumpSeconds: existing.startPumpSeconds ?? snapshot.bolus.startPumpSeconds,
                end: nil,
                endPumpSeconds: nil,
                deliveredUnits: nil,
                endReason: nil,
                sourceId: existing.sourceId ?? snapshot.bolus.sourceId
            )
        }
        if let last = snapshot.lastBolus, let existing = boluses[last.bolusId], existing.isFinished || !snapshot.bolus.active || snapshot.bolus.bolusId != last.bolusId {
            boluses[last.bolusId] = Bolus(
                bolusId: existing.bolusId,
                programmedUnits: existing.programmedUnits ?? last.requestedUnits,
                start: existing.start,
                startPumpSeconds: existing.startPumpSeconds,
                end: existing.end ?? instant(last.endPumpSeconds),
                endPumpSeconds: existing.endPumpSeconds ?? last.endPumpSeconds,
                deliveredUnits: last.deliveredUnits,
                endReason: existing.endReason ?? BolusEndReason(id: last.endReasonId),
                sourceId: existing.sourceId ?? last.sourceId
            )
        }
        if snapshot.basal.tempActive, let startSeconds = snapshot.basal.tempStartPumpSeconds,
           let index = tempRates.lastIndex(where: { !$0.isFinished && abs($0.start.timeIntervalSince(instant(startSeconds))) < 1 })
        {
            let open = tempRates[index]
            tempRates[index] = TempRate(
                tempRateId: open.tempRateId ?? snapshot.basal.tempRateId,
                rate: open.rate ?? snapshot.basal.tempRate,
                percent: open.percent ?? snapshot.basal.tempPercent,
                profileRate: open.profileRate ?? snapshot.basal.profileRate,
                start: open.start,
                startPumpSeconds: open.startPumpSeconds,
                scheduledEnd: open.scheduledEnd ?? snapshot.basal.tempEnd?.date,
                end: nil,
                endPumpSeconds: nil,
                timeLeft: nil
            )
        }

        let connections = log.filter { $0.kind == "connection" }.compactMap { entry -> Connection? in
            guard let connected = entry.connected else { return nil }
            return Connection(connected: connected, at: entry.time)
        }

        let sequences = entries.map(\.sequence)
        return PumpTimeline(
            boluses: bolusOrder.compactMap { boluses[$0] },
            tempRates: tempRates,
            suspends: suspends,
            alarms: alarms,
            connections: connections,
            unplaced: unplaced,
            historyRange: sequences.min().flatMap { min in sequences.max().map { min ... $0 } }
        )
    }

    /// pumpX2 `PumpingSuspendedHistoryLog.SuspendReason`, for a record whose context is missing.
    private static func suspendReasonName(_ reasonId: Int) -> String {
        switch reasonId {
        case 0: return "user"
        case 1: return "alarm"
        case 2: return "malfunction"
        case 6: return "plgs"
        default: return "reasonId \(reasonId)"
        }
    }

    // MARK: - Diff against a Loop oracle

    struct Tolerance {
        /// Allowed difference between a pump instant and the dose date the driver reported.
        var time: TimeInterval = 2
        /// Allowed difference in units (the pump's bolus increment is 0.001 U; deliveries are
        /// simulated at a rate, so a stepped estimate can differ by one tick's worth).
        var units: Double = 0.0005
        /// Allowed difference in U/h.
        var rate: Double = 0.005

        static let exact = Tolerance()
    }

    struct Mismatch: CustomStringConvertible, Equatable {
        let what: String
        let pump: String
        let reported: String
        var description: String { "\(what): pump \(pump), reported \(reported)" }
    }

    /// The result of comparing the oracle's live doses against the pump's records. Empty when the
    /// two ledgers agree.
    struct Diff: CustomStringConvertible {
        /// Pump deliveries with no live dose in the oracle.
        var missing: [String] = []
        /// Pump deliveries matched by more than one live dose.
        var duplicated: [String] = []
        /// Matched pairs whose fields disagree beyond tolerance.
        var mismatched: [Mismatch] = []
        /// Live oracle doses that match nothing the pump did.
        var extra: [String] = []

        var isEmpty: Bool { missing.isEmpty && duplicated.isEmpty && mismatched.isEmpty && extra.isEmpty }

        var description: String {
            if isEmpty { return "timeline and oracle agree" }
            var lines: [String] = []
            if !missing.isEmpty { lines.append("missing: \(missing)") }
            if !duplicated.isEmpty { lines.append("duplicated: \(duplicated)") }
            if !mismatched.isEmpty { lines.append("mismatched: \(mismatched.map(\.description))") }
            if !extra.isEmpty { lines.append("extra: \(extra)") }
            return lines.joined(separator: "\n")
        }
    }

    /// Compares the oracle's live doses with the pump's boluses, temp rates and suspends.
    ///
    /// Matching is by type and start time within `tolerance.time` (a bolus's driver-side start is
    /// when it was programmed; the pump's is when it began — the same second in lock-step). A
    /// finished pump bolus expects an immutable dose with its delivered volume and end; a running
    /// one expects a mutable dose. A temp rate expects `value` == its rate and the scheduled end
    /// while running, the actual end (and rate × duration delivered) once finished.
    func diff(against oracle: LoopDoseStoreOracle, tolerance: Tolerance = .exact) -> Diff {
        var diff = Diff()
        var claimed = Set<String>() // syncIdentifiers already matched to a pump record
        let doses = oracle.doses

        func near(_ a: Date?, _ b: Date?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.timeIntervalSince(b)) <= tolerance.time
        }

        for bolus in boluses {
            let label = "bolus \(bolus.bolusId) (\(bolus.programmedUnits.map { "\($0) U" } ?? "? U"))"
            let matches = doses.filter { $0.dose.type == .bolus && near($0.dose.startDate, bolus.start) }
            guard let match = matches.first else {
                diff.missing.append(label)
                continue
            }
            if matches.count > 1 {
                diff.duplicated.append("\(label): \(matches.map(LoopDoseStoreOracle.describe))")
            }
            matches.forEach { claimed.insert($0.syncIdentifier) }
            if let programmed = bolus.programmedUnits, abs(match.dose.programmedUnits - programmed) > tolerance.units {
                diff.mismatched.append(Mismatch(what: "\(label) programmed units", pump: "\(programmed)", reported: "\(match.dose.programmedUnits)"))
            }
            if bolus.isFinished {
                if match.isMutable {
                    diff.mismatched.append(Mismatch(what: "\(label) finished on the pump", pump: "ended \(bolus.end!)", reported: "still mutable"))
                } else {
                    if let delivered = bolus.deliveredUnits {
                        if let reported = match.dose.deliveredUnits {
                            if abs(reported - delivered) > tolerance.units {
                                diff.mismatched.append(Mismatch(what: "\(label) delivered units", pump: "\(delivered)", reported: "\(reported)"))
                            }
                        } else {
                            diff.mismatched.append(Mismatch(what: "\(label) delivered units", pump: "\(delivered)", reported: "nil"))
                        }
                    }
                    if !near(match.dose.endDate, bolus.end) {
                        diff.mismatched.append(Mismatch(what: "\(label) end", pump: "\(bolus.end!)", reported: "\(match.dose.endDate)"))
                    }
                }
            } else if !match.isMutable {
                diff.mismatched.append(Mismatch(what: "\(label) still running on the pump", pump: "running", reported: "immutable"))
            }
        }

        for temp in tempRates {
            let label = "temp rate \(temp.tempRateId.map(String.init) ?? "?") (\(temp.rate.map { "\($0) U/h" } ?? "?"))"
            let matches = doses.filter { $0.dose.type == .tempBasal && near($0.dose.startDate, temp.start) }
            guard let match = matches.first else {
                diff.missing.append(label)
                continue
            }
            if matches.count > 1 {
                diff.duplicated.append("\(label): \(matches.map(LoopDoseStoreOracle.describe))")
            }
            matches.forEach { claimed.insert($0.syncIdentifier) }
            if let rate = temp.rate, abs(match.dose.unitsPerHour - rate) > tolerance.rate {
                diff.mismatched.append(Mismatch(what: "\(label) rate", pump: "\(rate)", reported: "\(match.dose.unitsPerHour)"))
            }
            if temp.isFinished {
                if match.isMutable {
                    diff.mismatched.append(Mismatch(what: "\(label) finished on the pump", pump: "ended \(temp.end!)", reported: "still mutable"))
                } else {
                    if !near(match.dose.endDate, temp.end) {
                        diff.mismatched.append(Mismatch(what: "\(label) end", pump: "\(temp.end!)", reported: "\(match.dose.endDate)"))
                    }
                    if let delivered = temp.deliveredUnits, let reported = match.dose.deliveredUnits,
                       abs(reported - delivered) > max(tolerance.units, (temp.rate ?? 0) * tolerance.time / .hours(1))
                    {
                        diff.mismatched.append(Mismatch(what: "\(label) delivered units", pump: "\(delivered)", reported: "\(reported)"))
                    }
                }
            } else {
                if !match.isMutable {
                    diff.mismatched.append(Mismatch(what: "\(label) still running on the pump", pump: "running", reported: "immutable"))
                }
                if let scheduled = temp.scheduledEnd, !near(match.dose.endDate, scheduled) {
                    diff.mismatched.append(Mismatch(what: "\(label) scheduled end", pump: "\(scheduled)", reported: "\(match.dose.endDate)"))
                }
            }
        }

        for suspend in suspends {
            let label = "suspend at \(suspend.start) (\(suspend.reason ?? "?"))"
            let matches = doses.filter { $0.dose.type == .suspend && near($0.dose.startDate, suspend.start) }
            guard let match = matches.first else {
                diff.missing.append(label)
                continue
            }
            if matches.count > 1 {
                diff.duplicated.append("\(label): \(matches.map(LoopDoseStoreOracle.describe))")
            }
            matches.forEach { claimed.insert($0.syncIdentifier) }
            if let resumed = suspend.resumed, !near(match.dose.endDate, resumed) {
                diff.mismatched.append(Mismatch(what: "\(label) resume", pump: "\(resumed)", reported: "\(match.dose.endDate)"))
            }
        }

        for stored in doses where !claimed.contains(stored.syncIdentifier) {
            switch stored.dose.type {
            case .bolus, .tempBasal, .suspend:
                diff.extra.append(LoopDoseStoreOracle.describe(stored))
            case .basal, .resume:
                continue // scheduled-basal and resume markers have no pump-side record to diff against
            }
        }

        return diff
    }

    func assertMatches(_ oracle: LoopDoseStoreOracle, tolerance: Tolerance = .exact, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let result = diff(against: oracle, tolerance: tolerance)
        XCTAssertTrue(result.isEmpty, "pump timeline and Loop oracle disagree:\n\(result)\n\(message)", file: file, line: line)
    }
}
