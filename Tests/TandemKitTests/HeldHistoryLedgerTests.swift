@testable import TandemKit
import XCTest

final class HeldHistoryLedgerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let bolus = Data([0x01])
    private let suspend = Data([0x02])

    private func minutes(_ minutes: Double) -> Date {
        t0.addingTimeInterval(minutes * 60)
    }

    func testAnEventWarnsOnceHeldForFifteenMinutes() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 0], now: t0)
        ledger.update(examined: [bolus], held: [bolus: 0], now: minutes(10))

        XCTAssertTrue(ledger.entriesHeldTooLong(now: minutes(14)).isEmpty)
        XCTAssertEqual(ledger.entriesHeldTooLong(now: minutes(15)).map(\.raw), [bolus])
        XCTAssertEqual(ledger.entries.first?.firstHeldAt, t0)
    }

    func testAnEventALaterPassDatesLeaves() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus, suspend], held: [bolus: 0, suspend: 0], now: t0)

        ledger.update(examined: [bolus], held: [:], now: minutes(20))

        XCTAssertEqual(ledger.entries.map(\.raw), [suspend], "the pass that dated the bolus did not examine the suspend")
    }

    func testAnEventStopsWarningSixHoursAfterItWasFirstHeld() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 0], now: t0)

        XCTAssertFalse(ledger.entriesHeldTooLong(now: minutes(6 * 60 - 1)).isEmpty)
        XCTAssertTrue(ledger.isHolding(bolus, now: minutes(6 * 60 - 1)))
        XCTAssertTrue(ledger.entriesHeldTooLong(now: minutes(6 * 60)).isEmpty)
        XCTAssertFalse(ledger.isHolding(bolus, now: minutes(6 * 60)))
    }

    func testAnExtendedBolusCountsItsSixHoursFromItsProgrammedEnd() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 7200.0], now: t0)

        XCTAssertFalse(ledger.entriesHeldTooLong(now: minutes(8 * 60 - 1)).isEmpty)
        XCTAssertTrue(ledger.entriesHeldTooLong(now: minutes(8 * 60)).isEmpty)
    }

    func testAnExpiredEventStillHeldDoesNotStartWarningAgain() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 0], now: t0)

        ledger.update(examined: [bolus], held: [bolus: 0], now: minutes(7 * 60))

        XCTAssertEqual(ledger.entries.map(\.firstHeldAt), [t0])
        XCTAssertTrue(ledger.entriesHeldTooLong(now: minutes(8 * 60)).isEmpty)
    }

    func testAnEventNoPassHasHeldForADayIsForgotten() {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 0], now: t0)

        ledger.update(examined: [], held: [:], now: minutes(24 * 60 + 1))

        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testTheLedgerSurvivesARawValueRoundTrip() throws {
        var ledger = HeldHistoryLedger()
        ledger.update(examined: [bolus], held: [bolus: 3600], now: t0)

        XCTAssertEqual(try XCTUnwrap(HeldHistoryLedger(rawValue: ledger.rawValue)), ledger)
    }
}
