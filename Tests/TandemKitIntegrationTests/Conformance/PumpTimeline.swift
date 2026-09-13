import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// The pump's own record of what it delivered, rebuilt from the emulator's history log (the tail in
/// `GET /api/state` `history`), the live `bolus` / `basal` / `last_bolus` snapshot fields and the
/// connection entries of `GET /api/log`. This is the side of the ledger a driver's reports are
/// diffed against (guide §11 "diff your reported timeline"; plan "PumpTimeline").
///
/// Times are the pump's: history `time` is the record's instant on the pump clock (with any
/// `pump_offset_seconds` skew applied, as on the wire); `pumpSeconds` is the same instant in
/// seconds since the Tandem epoch.
struct PumpTimeline {
    // MARK: - Records

    enum BolusEndReason: Int {
        case unknown = 0
        case stopped = 1
        case completed = 3
        case other = -1

        init(id: Int?) {
            guard let id else { self = .unknown; return }
            self = BolusEndReason(rawValue: id) ?? .other
        }
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
        /// pumpX2 `BolusDeliveryHistoryLog` source id: 8 is an app-commanded bolus.
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
        /// When it actually ended (expiry, stop, or suspend); nil while running.
        let end: Date?
        let endPumpSeconds: Int?
        var isFinished: Bool { end != nil }
        /// rate × actual (or scheduled) duration, what a finalized `deliveredUnits` should read.
        var deliveredUnits: Double? {
            guard let rate, let until = end ?? scheduledEnd else { return nil }
            return rate * until.timeIntervalSince(start) / .hours(1)
        }
    }

    struct Suspend: Equatable {
        let reason: String?
        let start: Date
        let startPumpSeconds: Int
        let resumed: Date?
        let resumedPumpSeconds: Int?
    }

    struct Alarm: Equatable {
        let alarmId: Int?
        let reason: String?
        let message: String?
        let at: Date
        let pumpSeconds: Int
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

    /// Builds from a snapshot's history tail and, optionally, the request log's connection entries.
    /// Records with a sequence at or below `afterSequence` are ignored, so a test can start from the
    /// history the emulator had before it began.
    static func build(
        snapshot: FaketandemSnapshot,
        log: [FaketandemLogEntry] = [],
        afterSequence: Int = 0
    ) -> PumpTimeline {
        let entries = snapshot.history.entries.filter { $0.sequence > afterSequence }.sorted { $0.sequence < $1.sequence }

        var boluses: [Int: Bolus] = [:]
        var bolusOrder: [Int] = []
        var tempRates: [TempRate] = []
        var suspends: [Suspend] = []
        var alarms: [Alarm] = []
        var unplaced: [Unplaced] = []

        for entry in entries {
            let data = entry.data ?? [:]
            switch entry.type {
            case "BolusActivated", "BolusRequestedMsg1":
                // Protocol path writes bolusId/bolusSize (pkg/handler/router.go), harness path
                // bolusId/units/bolusSourceId (pkg/harness/actions.go actionBolusStart).
                guard let id = data["bolusId"]?.intValue else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no bolusId"))
                    continue
                }
                if boluses[id] != nil { continue } // BolusRequestedMsg1 after BolusActivated, or a repeat
                bolusOrder.append(id)
                boluses[id] = Bolus(
                    bolusId: id,
                    programmedUnits: data["bolusSize"]?.doubleValue ?? data["units"]?.doubleValue,
                    start: entry.time,
                    startPumpSeconds: entry.pumpTime,
                    end: nil,
                    endPumpSeconds: nil,
                    deliveredUnits: nil,
                    endReason: nil,
                    sourceId: data["bolusSourceId"]?.intValue
                )

            case "BolusCompleted":
                guard let id = data["bolusId"]?.intValue else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no bolusId"))
                    continue
                }
                let existing = boluses[id]
                if existing == nil { bolusOrder.append(id) }
                // The simulator's completion record carries no endReasonId; the harness's does.
                let reason = data["endReasonId"]?.intValue.map { BolusEndReason(id: $0) }
                boluses[id] = Bolus(
                    bolusId: id,
                    programmedUnits: existing?.programmedUnits ?? data["unitsTotal"]?.doubleValue,
                    start: existing?.start,
                    startPumpSeconds: existing?.startPumpSeconds,
                    end: entry.time,
                    endPumpSeconds: entry.pumpTime,
                    deliveredUnits: data["unitsDelivered"]?.doubleValue,
                    endReason: reason,
                    sourceId: existing?.sourceId
                )

            case "TempRateActivated":
                // Protocol path: percent, durationMilliseconds, tempRateId. Harness path: tempRate,
                // normalRate, percent, minutes, tempRateId.
                let minutes = data["minutes"]?.doubleValue
                    ?? data["durationMilliseconds"]?.doubleValue.map { $0 / 60_000 }
                let profile = data["normalRate"]?.doubleValue ?? snapshot.basal.profileRate
                let percent = data["percent"]?.intValue
                let rate = data["tempRate"]?.doubleValue ?? percent.map { profile * Double($0) / 100 }
                tempRates.append(TempRate(
                    tempRateId: data["tempRateId"]?.intValue,
                    rate: rate,
                    percent: percent,
                    profileRate: profile,
                    start: entry.time,
                    startPumpSeconds: entry.pumpTime,
                    scheduledEnd: minutes.map { entry.time.addingTimeInterval($0 * 60) },
                    end: nil,
                    endPumpSeconds: nil
                ))

            case "TempRateCompleted":
                // Carries only tempRate/normalRate: no id, no start. It can only close the most
                // recent open temp rate (see the emulator gaps in the report).
                guard let index = tempRates.lastIndex(where: { !$0.isFinished }) else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "no open temp rate to close"))
                    continue
                }
                let open = tempRates[index]
                tempRates[index] = TempRate(
                    tempRateId: open.tempRateId,
                    rate: open.rate ?? data["tempRate"]?.doubleValue,
                    percent: open.percent,
                    profileRate: open.profileRate ?? data["normalRate"]?.doubleValue,
                    start: open.start,
                    startPumpSeconds: open.startPumpSeconds,
                    scheduledEnd: open.scheduledEnd,
                    end: entry.time,
                    endPumpSeconds: entry.pumpTime
                )

            case "PumpingSuspended":
                // Harness path writes `reason` (user/occlusion/alarm); protocol path `reasonId`.
                let reason = data["reason"]?.stringValue
                    ?? data["reasonId"]?.intValue.map { "reasonId \($0)" }
                suspends.append(Suspend(reason: reason, start: entry.time, startPumpSeconds: entry.pumpTime, resumed: nil, resumedPumpSeconds: nil))

            case "PumpingResumed":
                if let index = suspends.lastIndex(where: { $0.resumed == nil }) {
                    let open = suspends[index]
                    suspends[index] = Suspend(
                        reason: open.reason,
                        start: open.start,
                        startPumpSeconds: open.startPumpSeconds,
                        resumed: entry.time,
                        resumedPumpSeconds: entry.pumpTime
                    )
                } else {
                    unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "resume without a suspend"))
                }

            case "AlarmActivated":
                alarms.append(Alarm(
                    alarmId: data["alarmId"]?.intValue,
                    reason: data["reason"]?.stringValue,
                    message: data["message"]?.stringValue,
                    at: entry.time,
                    pumpSeconds: entry.pumpTime
                ))

            default:
                unplaced.append(Unplaced(sequence: entry.sequence, type: entry.type, note: "not a delivery record"))
            }
        }

        // The live snapshot fills in what history cannot: a running bolus's start (the
        // protocol-path BolusActivated has it too, but only while the record is inside the tail),
        // and the last bolus's pump-side end and delivered volume.
        if snapshot.bolus.active, let start = snapshot.bolus.startTime?.date {
            let id = snapshot.bolus.bolusId
            if boluses[id] == nil {
                bolusOrder.append(id)
                boluses[id] = Bolus(
                    bolusId: id,
                    programmedUnits: snapshot.bolus.unitsTotal,
                    start: start,
                    startPumpSeconds: snapshot.bolus.startPumpSeconds,
                    end: nil,
                    endPumpSeconds: nil,
                    deliveredUnits: nil,
                    endReason: nil,
                    sourceId: snapshot.bolus.sourceId
                )
            }
        }
        if let last = snapshot.lastBolus, var bolus = boluses[last.bolusId] ?? Optional(Bolus(
            bolusId: last.bolusId,
            programmedUnits: last.requestedUnits,
            start: nil,
            startPumpSeconds: nil,
            end: last.endTime,
            endPumpSeconds: last.endPumpSeconds,
            deliveredUnits: last.deliveredUnits,
            endReason: BolusEndReason(id: last.endReasonId),
            sourceId: last.sourceId
        )) {
            if boluses[last.bolusId] == nil { bolusOrder.append(last.bolusId) }
            if bolus.end != nil || boluses[last.bolusId] == nil {
                bolus = Bolus(
                    bolusId: bolus.bolusId,
                    programmedUnits: bolus.programmedUnits ?? last.requestedUnits,
                    start: bolus.start,
                    startPumpSeconds: bolus.startPumpSeconds,
                    end: bolus.end ?? last.endTime,
                    endPumpSeconds: bolus.endPumpSeconds ?? last.endPumpSeconds,
                    deliveredUnits: last.deliveredUnits,
                    endReason: BolusEndReason(id: last.endReasonId),
                    sourceId: bolus.sourceId ?? last.sourceId
                )
            }
            boluses[last.bolusId] = bolus
        }
        if snapshot.basal.tempActive, let start = snapshot.basal.tempStart?.date,
           !tempRates.contains(where: { $0.start == start && !$0.isFinished })
        {
            tempRates.append(TempRate(
                tempRateId: snapshot.basal.tempRateId,
                rate: snapshot.basal.tempRate,
                percent: snapshot.basal.tempPercent,
                profileRate: snapshot.basal.profileRate,
                start: start,
                startPumpSeconds: snapshot.basal.tempStartPumpSeconds ?? 0,
                scheduledEnd: snapshot.basal.tempEnd?.date,
                end: nil,
                endPumpSeconds: nil
            ))
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
