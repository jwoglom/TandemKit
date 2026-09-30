@testable import TandemKit
import XCTest

final class BolusResolutionLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func event(_ kind: BolusResolutionLog.Kind, bolusId: Int = 1, at date: Date) -> BolusResolutionLog.Event {
        BolusResolutionLog.Event(date: date, kind: kind, bolusId: bolusId)
    }

    func testRecordingCountsTheKindAndKeepsTheEvent() {
        var log = BolusResolutionLog(countingSince: t0)

        log.record(event(.pumpBolusFound, bolusId: 7, at: t0))
        log.record(event(.pumpBolusFinalized, bolusId: 7, at: t0.addingTimeInterval(60)))
        log.record(event(.pumpBolusFound, bolusId: 8, at: t0.addingTimeInterval(120)))

        XCTAssertEqual(log.count(.pumpBolusFound), 2)
        XCTAssertEqual(log.count(.pumpBolusFinalized), 1)
        XCTAssertEqual(log.count(.heldBolusFinalizedWithFallback), 0)
        XCTAssertEqual(log.events.map(\.bolusId), [7, 7, 8])
        XCTAssertTrue(log.contains(.pumpBolusFound, bolusId: 8))
        XCTAssertFalse(log.contains(.pumpBolusFinalized, bolusId: 8))
    }

    func testEventsExpireButCountsDoNot() {
        var log = BolusResolutionLog(countingSince: t0)
        log.record(event(.bolusHeld, at: t0))

        log.record(event(.heldBolusFinalizedWithFallback, at: t0.addingTimeInterval(BolusResolutionLog.retention + 1)))

        XCTAssertEqual(log.events.map(\.kind), [.heldBolusFinalizedWithFallback])
        XCTAssertEqual(log.count(.bolusHeld), 1)
    }

    func testEventsAreCapped() {
        var log = BolusResolutionLog(countingSince: t0)
        for index in 0 ..< BolusResolutionLog.maximumEvents + 5 {
            log.record(event(.pumpBolusFound, bolusId: index, at: t0.addingTimeInterval(TimeInterval(index))))
        }

        XCTAssertEqual(log.events.count, BolusResolutionLog.maximumEvents)
        XCTAssertEqual(log.events.first?.bolusId, 5, "The oldest go first")
        XCTAssertEqual(log.count(.pumpBolusFound), BolusResolutionLog.maximumEvents + 5)
    }

    func testResetStartsCountingAgain() {
        var log = BolusResolutionLog(countingSince: t0)
        log.record(event(.bolusHeld, at: t0))

        let later = t0.addingTimeInterval(3600)
        log.reset(now: later)

        XCTAssertEqual(log, BolusResolutionLog(countingSince: later))
    }

    func testRoundTripsThroughRawValue() {
        var log = BolusResolutionLog(countingSince: t0)
        log.record(BolusResolutionLog.Event(
            date: t0,
            kind: .pumpBolusFound,
            bolusId: 42,
            doseDate: t0.addingTimeInterval(-300),
            programmedUnits: 2.0,
            isMutable: true,
            automatic: false,
            bolusSource: BolusDeliveryHistoryLog.BolusSource.quickBolus.rawValue
        ))
        log.record(BolusResolutionLog.Event(
            date: t0.addingTimeInterval(60),
            kind: .heldBolusFinalizedWithFallback,
            bolusId: nil,
            doseDate: t0,
            programmedUnits: 1.0,
            deliveredUnits: 1.0,
            fallbackUnits: 1.0,
            automatic: true,
            note: "Superseded by bolus 43"
        ))

        XCTAssertEqual(BolusResolutionLog(rawValue: log.rawValue), log)
    }

    func testAnEventOfAKindThisBuildDoesNotKnowIsDropped() {
        var raw = BolusResolutionLog(countingSince: t0).rawValue
        let events: [[String: Any]] = [
            ["date": t0.timeIntervalSinceReferenceDate, "kind": "somethingNewer", "isMutable": false],
            BolusResolutionLog.Event(date: t0, kind: .bolusHeld, bolusId: 3).rawValue
        ]
        raw["events"] = events
        raw["counts"] = ["somethingNewer": 4, BolusResolutionLog.Kind.bolusHeld.rawValue: 1]

        let log = BolusResolutionLog(rawValue: raw)

        XCTAssertEqual(log?.events.map(\.kind), [.bolusHeld])
        XCTAssertEqual(log?.count(.bolusHeld), 1)
    }

    func testSurvivesTheManagerStateRoundTrip() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.bolusResolutionLog.record(event(.appBolusFinalizedFromHistory, bolusId: 9, at: t0))

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.bolusResolutionLog, state.bolusResolutionLog)
    }
}
