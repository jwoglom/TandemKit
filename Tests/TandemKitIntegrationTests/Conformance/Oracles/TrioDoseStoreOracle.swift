import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Replays `hasNewPumpEvents` batches the way Trio consumes them, so a report that is right for
/// Loop's `DoseStore` and wrong for Trio's pump history shows up (audit G01).
///
/// Trio's path, in `/Users/james/repos/Trio-tandem/Trio/Sources` when written:
/// - `APS/DeviceDataManager.swift:600-625` (DDM): the delegate method ignores `lastReconciliation`
///   and `replacePendingEvents`, drops any `.tempBasal` whose `unitsPerHour` exceeds
///   `pumpSettings.maxBasal`, hands the rest to `PumpHistoryStorage.storePumpEvents`, and remembers
///   `events.last?.date` as `lastEventDate` (which feeds `startDateToFilterNewPumpEvents`).
/// - `APS/Storage/PumpHistoryStorage.swift:49-197` (PHS): one `PumpEventStored` row per
///   `(timestamp, type)`, where `type` is a `PumpEventStored.EventType` string. Nothing reads `raw`,
///   `syncIdentifier` or `isMutable`.
final class TrioDoseStoreOracle: DoseOracle {
    /// `PumpEventStored.EventType` raw values (`Models/PumpHistoryEvent.swift:55-66`), for the types
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
    }

    /// One `PumpEventStored` row with its `BolusStored` / `TempBasalStored` child.
    struct StoredEvent: Equatable {
        let timestamp: Date
        let type: EventType
        /// `BolusStored.amount` (PHS:135), corrected downward only (PHS:112-121).
        var bolusAmount: Decimal?
        /// `BolusStored.isSMB` (PHS:137): `dose.automatic ?? true`.
        var isSMB: Bool?
        /// `BolusStored.isExternal` (PHS:136): `dose.manuallyEntered`.
        var isExternal: Bool?
        /// `TempBasalStored.rate` (PHS:158).
        var tempBasalRate: Decimal?
        /// `TempBasalStored.duration` in whole minutes (PHS:157).
        var tempBasalDurationMinutes: Int?
        /// `PumpEventStored.note` for alarms (PHS:175): the event title.
        var note: String?
        /// How many times the smaller-amount update fired (PHS:112-121).
        var downwardUpdates: Int
        /// The event batch (0-based call index) that created the row.
        let createdInCall: Int
    }

    /// Why an event did not produce or change a row. Tests assert on these to show what Trio lost.
    enum Skip: Equatable {
        /// DDM:612-616 — temp basal above `maxBasal`.
        case tempBasalAboveMaxBasal(unitsPerHour: Double)
        /// PHS:144-146 — a temp basal carrying `deliveredUnits` (a finalization or cancel) is skipped.
        case tempBasalWithDeliveredUnits
        /// PHS:81-83 / PHS:108-123 — a `(timestamp, type)` row already existed and was not changed.
        case duplicate(EventType)
        /// PHS:181-182 — `.basal`, `.alarmClear`, `.replaceComponent(.reservoir)`, nil type, or a
        /// dose-less bolus/temp basal.
        case unhandled(String)
    }

    struct SkippedEvent: Equatable {
        let call: Int
        let event: NewPumpEvent
        let reason: Skip
    }

    /// `pumpSettings.maxBasal` for the DDM filter.
    let maxBasal: Double
    /// `preferences.bolusIncrement` for `roundDose` (PHS:44-47, 100-103); Trio's default is 0.1.
    let bolusIncrement: Double

    private(set) var events: [StoredEvent] = []
    private(set) var skipped: [SkippedEvent] = []
    /// DDM:619 — `events.last?.date` of the most recent non-empty batch that stored.
    private(set) var lastEventDate: Date?
    private(set) var callCount = 0

    init(maxBasal: Double = 10, bolusIncrement: Double = 0.1) {
        self.maxBasal = maxBasal
        self.bolusIncrement = bolusIncrement
    }

    // MARK: - Views

    var boluses: [StoredEvent] { events.filter { $0.type == .bolus } }
    var tempBasals: [StoredEvent] { events.filter { $0.type == .tempBasal } }
    var suspends: [StoredEvent] { events.filter { $0.type == .pumpSuspend } }
    var resumes: [StoredEvent] { events.filter { $0.type == .pumpResume } }
    var alarms: [StoredEvent] { events.filter { $0.type == .pumpAlarm } }

    func event(timestamp: Date, type: EventType) -> StoredEvent? {
        events.first { $0.timestamp == timestamp && $0.type == type }
    }

    /// DDM:661 — what Trio would answer to `startDateToFilterNewPumpEvents(for:)`.
    func startDateToFilterNewPumpEvents(now: Date) -> Date {
        lastEventDate?.addingTimeInterval(-.minutes(15)) ?? now.addingTimeInterval(-.hours(2))
    }

    // MARK: - DeviceDataManager + PumpHistoryStorage fold

    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation _: Date?, replacePendingEvents _: Bool, now _: Date) {
        let call = callCount
        callCount += 1

        // DDM:612-616 — the maxBasal filter runs before storage.
        var accepted: [NewPumpEvent] = []
        for event in events {
            if event.type == .tempBasal, let rate = event.dose?.unitsPerHour, rate > maxBasal {
                skipped.append(SkippedEvent(call: call, event: event, reason: .tempBasalAboveMaxBasal(unitsPerHour: rate)))
            } else {
                accepted.append(event)
            }
        }

        storePumpEvents(accepted, call: call)

        // DDM:619 — after a successful store, even when nothing was written.
        if let last = accepted.last {
            lastEventDate = last.date
        }
    }

    /// PHS:49-197.
    private func storePumpEvents(_ events: [NewPumpEvent], call: Int) {
        for event in events {
            switch event.type {
            case .bolus:
                // PHS:98-139.
                guard let dose = event.dose else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled("bolus without dose")))
                    continue
                }
                let amount = roundDose(dose.unitsInDeliverableIncrements, toIncrement: bolusIncrement)
                if let index = index(timestamp: event.date, type: .bolus) {
                    // PHS:108-123 — duplicate; only a smaller amount updates the stored bolus.
                    if let existing = self.events[index].bolusAmount, amount < existing {
                        self.events[index].bolusAmount = amount
                        self.events[index].isSMB = dose.automatic ?? true
                        self.events[index].downwardUpdates += 1
                    }
                    skipped.append(SkippedEvent(call: call, event: event, reason: .duplicate(.bolus)))
                    continue
                }
                self.events.append(StoredEvent(
                    timestamp: event.date,
                    type: .bolus,
                    bolusAmount: amount,
                    isSMB: dose.automatic ?? true,
                    isExternal: dose.manuallyEntered,
                    downwardUpdates: 0,
                    createdInCall: call
                ))

            case .tempBasal:
                // PHS:141-159.
                guard let dose = event.dose else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled("tempBasal without dose")))
                    continue
                }
                if dose.deliveredUnits != nil {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .tempBasalWithDeliveredUnits))
                    continue
                }
                guard index(timestamp: event.date, type: .tempBasal) == nil else {
                    skipped.append(SkippedEvent(call: call, event: event, reason: .duplicate(.tempBasal)))
                    continue
                }
                let minutes = dose.endDate.timeIntervalSince(dose.startDate) / 60
                self.events.append(StoredEvent(
                    timestamp: event.date,
                    type: .tempBasal,
                    tempBasalRate: Decimal(dose.unitsPerHour),
                    tempBasalDurationMinutes: Int(minutes.rounded()),
                    downwardUpdates: 0,
                    createdInCall: call
                ))

            case .suspend:
                makeEventIfNew(timestamp: event.date, type: .pumpSuspend, event: event, call: call)
            case .resume:
                makeEventIfNew(timestamp: event.date, type: .pumpResume, event: event, call: call)
            case .rewind:
                makeEventIfNew(timestamp: event.date, type: .rewind, event: event, call: call)
            case .prime:
                makeEventIfNew(timestamp: event.date, type: .prime, event: event, call: call)
            case .alarm:
                // PHS:173-175.
                if let index = makeEventIfNew(timestamp: event.date, type: .pumpAlarm, event: event, call: call) {
                    self.events[index].note = event.title
                }
            case .replaceComponent(componentType: .infusionSet), .replaceComponent(componentType: .pump):
                makeEventIfNew(timestamp: event.date, type: .siteChange, event: event, call: call)
            default:
                // PHS:181-182 — .basal, .alarmClear, .replaceComponent(.reservoir), nil.
                skipped.append(SkippedEvent(call: call, event: event, reason: .unhandled(String(describing: event.type))))
            }
        }
    }

    /// PHS:79-94.
    @discardableResult
    private func makeEventIfNew(timestamp: Date, type: EventType, event: NewPumpEvent, call: Int) -> Int? {
        guard index(timestamp: timestamp, type: type) == nil else {
            skipped.append(SkippedEvent(call: call, event: event, reason: .duplicate(type)))
            return nil
        }
        events.append(StoredEvent(timestamp: timestamp, type: type, downwardUpdates: 0, createdInCall: call))
        return events.count - 1
    }

    /// PHS:69-71 — the dedup key is the exact timestamp plus the type string.
    private func index(timestamp: Date, type: EventType) -> Int? {
        events.firstIndex { $0.timestamp == timestamp && $0.type == type }
    }

    /// PHS:44-47.
    private func roundDose(_ dose: Double, toIncrement increment: Double) -> Decimal {
        Decimal((dose / increment).rounded() * increment)
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

    /// No two rows share `(timestamp, type)`; Trio's own constraint would refuse the second.
    func assertNoDuplicates(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        var seen = Set<String>()
        for row in events {
            let key = "\(row.timestamp.timeIntervalSinceReferenceDate)|\(row.type.rawValue)"
            XCTAssertTrue(seen.insert(key).inserted, "duplicate Trio row \(row). \(message)", file: file, line: line)
        }
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
