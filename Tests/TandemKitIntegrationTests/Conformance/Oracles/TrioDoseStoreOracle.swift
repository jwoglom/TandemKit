import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Replays `hasNewPumpEvents` batches the way Trio consumes them, so a report that is right for
/// Loop's `DoseStore` and wrong for Trio's pump history shows up (audit G01).
///
/// Trio's path since nightscout/Trio#1300, in `Trio/Sources` of the Trio workspace TandemKit builds in:
/// - `APS/DeviceDataManager.swift:539-578` (DDM): drops any `.tempBasal` whose `unitsPerHour`
///   exceeds `pumpSettings.maxBasal`, hands the rest and `replacePendingEvents` to
///   `PumpHistoryStorage.storePumpEvents`, and sets `lastEventDate` to the last one's date, nil for
///   an empty batch. `lastReconciliation` is ignored.
/// - `APS/Storage/PumpHistoryStorage.swift:63-325` (PHS): one `PumpEventStored` row per event,
///   matched by `syncIdentifier`, then by `(timestamp, type, isScheduledBasal)`. A matched mutable
///   row takes the event's values; a finalized one never changes. `.basal` is stored as a
///   zero-length `TempBasal` row flagged `isScheduledBasal`. A replacing batch deletes every mutable
///   row it did not match or create.
/// - `APS/OpenAPSSwift/Iob/IobHistory.swift` (IH) and `Model/Helper/PumpEvent+helper.swift`: IOB
///   reads each `TempBasal` row at its `timestamp`, `rate` and whole-minute `duration`; never its
///   `deliveredUnits`, which only TDD reads.
final class TrioDoseStoreOracle: DoseOracle {
    /// `PumpEventStored.EventType` raw values (`Models/PumpHistoryEvent.swift`), for the types
    /// `storePumpEvents` writes.
    enum EventType: String {
        case bolus = "Bolus"
        case tempBasal = "TempBasal"
        case pumpSuspend = "PumpSuspend"
        case pumpResume = "PumpResume"
        case pumpAlarm = "PumpAlarm"
        case rewind = "Rewind"
        case prime = "Prime"
        case siteChange = "Site Change"

        /// PHS:683-701, `PumpEventType.storedEventType`.
        init?(_ type: PumpEventType?) {
            switch type {
            case .alarm: self = .pumpAlarm
            case .basal, .tempBasal: self = .tempBasal
            case .bolus: self = .bolus
            case .prime: self = .prime
            case .resume: self = .pumpResume
            case .rewind: self = .rewind
            case .suspend: self = .pumpSuspend
            case .replaceComponent(componentType: .infusionSet), .replaceComponent(componentType: .pump): self = .siteChange
            default: return nil
            }
        }
    }

    /// One `PumpEventStored` row with its `BolusStored` / `TempBasalStored` child.
    struct StoredEvent: Equatable {
        /// `min(event.date, now)` at creation (PHS:130); never updated.
        let timestamp: Date
        let type: EventType
        let syncIdentifier: String?
        var isMutable: Bool
        /// `BolusStored.amount`: the dose's deliverable units at creation, its `deliveredUnits` once
        /// an update carries them (PHS:249-266).
        var bolusAmount: Decimal?
        var programmedAmount: Decimal?
        /// `dose.automatic ?? true`.
        var isSMB: Bool?
        /// `dose.manuallyEntered`.
        var isExternal: Bool?
        var tempBasalRate: Decimal?
        /// `Int16(round(minutes))` of the dose's span, 0 for a scheduled basal (PHS:232-245).
        var tempBasalDurationMinutes: Int?
        var tempBasalStart: Date?
        var tempBasalEnd: Date?
        var deliveredUnits: Decimal?
        var isScheduledBasal: Bool
        /// The event title, for alarms.
        var note: String?
        /// How many times a later report updated this row while it was mutable.
        var updateCount: Int
        /// The event batch (0-based call index) that created the row.
        let createdInCall: Int
    }

    /// Why an event did not produce or change a row. Tests assert on these to show what Trio lost.
    enum Skip: Equatable {
        /// DDM:552-556 — temp basal above `maxBasal`.
        case tempBasalAboveMaxBasal(unitsPerHour: Double)
        /// PHS:117-125 — it matched a row that was already finalized, or carried no dose to update one with.
        case duplicate(EventType)
        /// PHS:102 / 143-145 / 161-163 — no stored type, or a bolus or temp basal without a dose.
        case unhandled(String)
    }

    struct SkippedEvent: Equatable {
        let call: Int
        let event: NewPumpEvent
        let reason: Skip
    }

    struct PurgedEvent: Equatable {
        let call: Int
        let row: StoredEvent
    }

    /// `pumpSettings.maxBasal` for the DDM filter.
    let maxBasal: Double
    /// `preferences.bolusIncrement` for `roundDose` (PHS:46-49); Trio's default is 0.1.
    let bolusIncrement: Double

    private(set) var events: [StoredEvent] = []
    private(set) var skipped: [SkippedEvent] = []
    /// Mutable rows a replacing batch deleted (PHS:195-207).
    private(set) var purged: [PurgedEvent] = []
    /// DDM:562 — the last stored event's date of the most recent batch.
    private(set) var lastEventDate: Date?
    private(set) var callCount = 0

    init(maxBasal: Double = 10, bolusIncrement: Double = 0.1) {
        self.maxBasal = maxBasal
        self.bolusIncrement = bolusIncrement
    }

    // MARK: - Views

    var boluses: [StoredEvent] { events.filter { $0.type == .bolus } }
    /// Temp basal rows, without the scheduled-basal rows that share their type.
    var tempBasals: [StoredEvent] { events.filter { $0.type == .tempBasal && !$0.isScheduledBasal } }
    var scheduledBasals: [StoredEvent] { events.filter { $0.type == .tempBasal && $0.isScheduledBasal } }
    var suspends: [StoredEvent] { events.filter { $0.type == .pumpSuspend } }
    var resumes: [StoredEvent] { events.filter { $0.type == .pumpResume } }
    var alarms: [StoredEvent] { events.filter { $0.type == .pumpAlarm } }

    func event(timestamp: Date, type: EventType) -> StoredEvent? {
        events.first { $0.timestamp == timestamp && $0.type == type }
    }

    func event(syncIdentifier: String) -> StoredEvent? {
        events.first { $0.syncIdentifier == syncIdentifier }
    }

    /// DDM:613-615 — what Trio would answer to `startDateToFilterNewPumpEvents(for:)`.
    func startDateToFilterNewPumpEvents(now: Date) -> Date {
        lastEventDate?.addingTimeInterval(-.minutes(15)) ?? now.addingTimeInterval(-.hours(2))
    }

    // MARK: - DeviceDataManager + PumpHistoryStorage fold

    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation _: Date?, replacePendingEvents: Bool, now: Date) {
        let call = callCount
        callCount += 1

        var accepted: [NewPumpEvent] = []
        for event in events {
            if event.type == .tempBasal, let rate = event.dose?.unitsPerHour, rate > maxBasal {
                skipped.append(SkippedEvent(call: call, event: event, reason: .tempBasalAboveMaxBasal(unitsPerHour: rate)))
            } else {
                accepted.append(event)
            }
        }

        storePumpEvents(accepted, replacePendingEvents: replacePendingEvents, call: call, now: now)
        lastEventDate = accepted.last?.date
    }

    /// PHS:63-221.
    private func storePumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool, call: Int, now: Date) {
        var asserted = Set<Int>()

        for event in events {
            guard let type = EventType(event.type) else {
                skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled(String(describing: event.type))))
                continue
            }
            let isScheduledBasal = event.type == .basal
            let syncIdentifier = event.dose?.syncIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            let match = syncIdentifier.flatMap { id in self.events.firstIndex { $0.syncIdentifier == id } }
                ?? self.events.firstIndex {
                    $0.timestamp == event.date && $0.type == type && $0.isScheduledBasal == isScheduledBasal
                }

            if let match {
                asserted.insert(match)
                if self.events[match].isMutable, let dose = event.dose {
                    update(&self.events[match], with: dose)
                } else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .duplicate(type)))
                }
                continue
            }

            var row = StoredEvent(
                timestamp: min(event.date, now),
                type: type,
                syncIdentifier: syncIdentifier,
                isMutable: event.dose?.isMutable ?? false,
                isScheduledBasal: false,
                updateCount: 0,
                createdInCall: call
            )
            switch type {
            case .bolus:
                guard let dose = event.dose else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled("bolus without dose")))
                    continue
                }
                row.bolusAmount = roundDose(dose.unitsInDeliverableIncrements)
                row.programmedAmount = roundDose(dose.programmedUnits)
                row.isExternal = dose.manuallyEntered
                row.isSMB = dose.automatic ?? true
            case .tempBasal:
                guard let dose = event.dose else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled("tempBasal without dose")))
                    continue
                }
                setTempBasal(&row, from: dose, isScheduledBasal: isScheduledBasal)
            case .pumpAlarm:
                row.note = event.title
            default:
                break
            }
            self.events.append(row)
            asserted.insert(self.events.count - 1)
        }

        if replacePendingEvents {
            let orphans = self.events.indices.filter { self.events[$0].isMutable && !asserted.contains($0) }
            purged += orphans.map { PurgedEvent(call: call, row: self.events[$0]) }
            for index in orphans.reversed() {
                self.events.remove(at: index)
            }
        }
    }

    /// PHS:247-325.
    private func update(_ row: inout StoredEvent, with dose: DoseEntry) {
        switch row.type {
        case .bolus:
            if let delivered = dose.deliveredUnits {
                row.bolusAmount = roundDose(delivered)
            }
            row.isSMB = dose.automatic ?? true
        case .tempBasal:
            setTempBasal(&row, from: dose, isScheduledBasal: dose.type == .basal)
        default:
            break
        }
        row.isMutable = dose.isMutable
        row.updateCount += 1
    }

    /// PHS:150-160 and 232-245: a scheduled basal is stored open-ended, as a zero-length span.
    private func setTempBasal(_ row: inout StoredEvent, from dose: DoseEntry, isScheduledBasal: Bool) {
        row.isScheduledBasal = isScheduledBasal
        row.tempBasalRate = Decimal(dose.unitsPerHour)
        row.tempBasalStart = dose.startDate
        if isScheduledBasal {
            row.tempBasalDurationMinutes = 0
            row.tempBasalEnd = dose.startDate
        } else {
            row.tempBasalDurationMinutes = Int((dose.endDate.timeIntervalSince(dose.startDate) / 60).rounded())
            row.tempBasalEnd = dose.endDate
        }
        row.deliveredUnits = dose.deliveredUnits.map { Decimal($0) }
    }

    private func roundDose(_ dose: Double) -> Decimal {
        Decimal((dose / bolusIncrement).rounded() * bolusIncrement)
    }

    // MARK: - IOB

    /// A stretch oref counts at one absolute rate.
    struct BasalSegment: Equatable {
        let start: Date
        let end: Date
        let rate: Double
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    enum IOBError: Error, Equatable {
        /// IH:132-136 — a suspend and a resume in the same second, which fails the whole IOB run.
        case pumpSuspendResumeMismatch
    }

    /// The temp basal history `IobHistory.calcTempTreatments` builds at `clock`, with
    /// `suspendZerosIob`: every `TempBasal` row by timestamp, each cut at the next one's timestamp,
    /// so two at one timestamp leave the first zero-length; then cut around the suspends, which run
    /// at zero.
    func basalSegments(clock: Date) throws -> [BasalSegment] {
        let rows = events.enumerated()
            .filter { $0.element.type == .tempBasal && $0.element.timestamp <= clock }
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)

        // IH:69-110: the trailing zero temp a minute past the clock only stops the last row.
        var temps = rows.map { row in
            BasalSegment(
                start: row.timestamp,
                end: row.timestamp.addingTimeInterval(.minutes(Double(row.tempBasalDurationMinutes ?? 0))),
                rate: NSDecimalNumber(decimal: row.tempBasalRate ?? 0).doubleValue
            )
        } + [BasalSegment(start: clock.addingTimeInterval(.minutes(1)), end: clock.addingTimeInterval(.minutes(1)), rate: 0)]
        for index in temps.indices.dropLast() where temps[index].end > temps[index + 1].start {
            temps[index] = BasalSegment(start: temps[index].start, end: temps[index + 1].start, rate: temps[index].rate)
        }

        let suspends = try suspendSpans(clock: clock)
        var cut: [BasalSegment] = []
        for temp in temps {
            cut += Self.cut(temp, around: suspends)
        }
        return (cut + suspends.map { BasalSegment(start: $0.start, end: $0.end, rate: 0) })
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
    }

    /// Insulin delivered above (or, negative, below) `scheduledRate` from `start` to `end`, as oref
    /// reads these rows at `clock`. Exact; oref then rounds each 30-minute piece to 0.05 U.
    func netBasalUnits(from start: Date, to end: Date, clock: Date, scheduledRate: (Date) -> Double) throws -> Double {
        try basalSegments(clock: clock).reduce(0) { total, segment in
            let lo = max(segment.start, start)
            let hi = min(segment.end, end)
            guard hi > lo else { return total }
            return total + Self.integrate(from: lo, to: hi) { segment.rate - scheduledRate($0) }
        }
    }

    /// Bolus and net basal insulin on board at `time`, each decaying linearly over `duration` as
    /// `LoopDoseStoreOracle.iob(at:)` does, so the two hosts' counts can be compared.
    func iob(at time: Date, scheduledRate: (Date) -> Double, duration: TimeInterval = .hours(5)) throws -> Double {
        let bolusIOB = boluses.reduce(0.0) { total, row in
            let units = NSDecimalNumber(decimal: row.bolusAmount ?? 0).doubleValue
            guard time > row.timestamp else { return total }
            return total + units * max(0, 1 - time.timeIntervalSince(row.timestamp) / duration)
        }
        let basalIOB = try basalSegments(clock: time).reduce(0.0) { total, segment in
            let lo = max(segment.start, time.addingTimeInterval(-duration))
            let hi = min(segment.end, time)
            guard hi > lo else { return total }
            return total + Self.integrate(from: lo, to: hi) { date in
                (segment.rate - scheduledRate(date)) * (1 - time.timeIntervalSince(date) / duration)
            }
        }
        return bolusIOB + basalIOB
    }

    /// IH:120-160 — repeats dropped; a leading resume means suspended since 36 hours back, a
    /// trailing suspend suspended until `clock`.
    private func suspendSpans(clock: Date) throws -> [(start: Date, end: Date)] {
        var transitions: [StoredEvent] = []
        for row in events.filter({ ($0.type == .pumpSuspend || $0.type == .pumpResume) && $0.timestamp <= clock })
            .sorted(by: { $0.timestamp < $1.timestamp })
            where transitions.last?.type != row.type
        {
            transitions.append(row)
        }
        for (current, next) in zip(transitions, transitions.dropFirst()) where current.timestamp == next.timestamp {
            throw IOBError.pumpSuspendResumeMismatch
        }

        var spans = zip(transitions, transitions.dropFirst()).compactMap { current, next in
            current.type == .pumpSuspend ? (start: current.timestamp, end: next.timestamp) : nil
        }
        let historyStart = clock.addingTimeInterval(-.hours(36))
        if let first = transitions.first, first.type == .pumpResume, historyStart < first.timestamp {
            spans.append((historyStart, first.timestamp))
        }
        if let last = transitions.last, last.type == .pumpSuspend {
            spans.append((last.timestamp, clock))
        }
        return spans.sorted { $0.start < $1.start }
    }

    /// IH:173-223, including its resumption of a temp after a suspend inside it.
    private static func cut(_ temp: BasalSegment, around suspends: [(start: Date, end: Date)]) -> [BasalSegment] {
        guard temp.duration > 0 else { return [temp] }
        for (index, suspend) in suspends.enumerated() where temp.start < suspend.end && suspend.start < temp.end {
            switch (temp.start < suspend.start, temp.end > suspend.end) {
            case (false, false):
                return []
            case (true, false):
                return [BasalSegment(start: temp.start, end: suspend.start, rate: temp.rate)]
            case (false, true):
                return cut(BasalSegment(start: suspend.end, end: temp.end, rate: temp.rate), around: Array(suspends.dropFirst(index + 1)))
            case (true, true):
                return [BasalSegment(start: temp.start, end: suspend.start, rate: temp.rate)]
                    + cut(BasalSegment(start: suspend.end, end: temp.end, rate: temp.rate), around: Array(suspends.dropFirst(index + 1)))
            }
        }
        return [temp]
    }

    /// A schedule changes at most every 30 minutes, so one-second steps are exact for a step
    /// function and close enough for the decay kernel.
    static func integrate(from start: Date, to end: Date, _ f: (Date) -> Double) -> Double {
        let span = end.timeIntervalSince(start)
        let steps = max(1, Int(span.rounded(.up)))
        let step = span / Double(steps)
        return (0 ..< steps).reduce(0) { total, i in
            total + f(start.addingTimeInterval((Double(i) + 0.5) * step)) * step / .hours(1)
        }
    }

    // MARK: - Assertions

    /// Exactly one bolus row at `date`, with this final amount.
    @discardableResult
    func assertSingleBolus(
        at date: Date,
        amount: Double,
        accuracy: Double = 0.0005,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> StoredEvent? {
        let rows = boluses.filter { $0.timestamp == date }
        guard rows.count == 1, let row = rows.first else {
            XCTFail("expected one Trio bolus row at \(date), found \(rows.count); all: \(boluses). \(message)", file: file, line: line)
            return nil
        }
        XCTAssertEqual(
            (row.bolusAmount ?? -1 as Decimal).doubleValue,
            amount,
            accuracy: accuracy,
            "Trio bolus amount at \(date). \(message)",
            file: file,
            line: line
        )
        return row
    }

    /// No two rows share a `syncIdentifier`, or `(timestamp, type, isScheduledBasal)`, the keys Trio
    /// matches a report on; a second row on either is a dose counted twice.
    func assertNoDuplicates(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        var seenIdentifiers = Set<String>()
        var seenKeys = Set<String>()
        for row in events {
            if let identifier = row.syncIdentifier {
                XCTAssertTrue(seenIdentifiers.insert(identifier).inserted, "duplicate Trio syncIdentifier \(row). \(message)", file: file, line: line)
            }
            let key = "\(row.timestamp.timeIntervalSinceReferenceDate)|\(row.type.rawValue)|\(row.isScheduledBasal)"
            XCTAssertTrue(seenKeys.insert(key).inserted, "duplicate Trio row \(row). \(message)", file: file, line: line)
        }
    }

    /// No two `TempBasal` rows start in the same second: oref's IOB pairs their rates and durations
    /// in an unspecified order and keeps one of them zero-length.
    func assertNoSameSecondBasalRows(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let starts = events.filter { $0.type == .tempBasal }.map { $0.timestamp.timeIntervalSinceReferenceDate.rounded(.down) }
        XCTAssertEqual(Set(starts).count, starts.count, "Trio basal rows share a second: \(events.filter { $0.type == .tempBasal }). \(message)", file: file, line: line)
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
