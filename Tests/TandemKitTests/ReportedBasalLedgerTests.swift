import LoopKit
@testable import TandemKit
import XCTest

final class ReportedBasalLedgerTests: XCTestCase {
    private let t0 = PumpBasalHistory.date(0)
    private lazy var schedule = HostBasalSchedule(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func temp(_ rate: Double, at start: TimeInterval, minutes: Double = 30, endingAt end: TimeInterval? = nil, raw: String? = nil) -> NewPumpEvent {
        let dose = UnfinalizedDose(tempRate: rate, duration: .minutes(minutes), automatic: true, insulinType: .novolog, startDate: at(start))
        let entry = dose.toDoseEntry(isMutable: end == nil, endDate: end.map(at), now: at(start))
        let event = NewPumpEvent.tempBasal(dose: entry, date: entry.startDate)
        return raw.map { NewPumpEvent(date: event.date, dose: entry, raw: Data($0.utf8), title: event.title) } ?? event
    }

    private func marker(_ rate: Double = 1.0, at start: TimeInterval) -> NewPumpEvent {
        let dose = UnfinalizedDose(basalRate: rate, insulinType: .novolog, startDate: at(start))
        return NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate)
    }

    private func suspend(at start: TimeInterval) -> NewPumpEvent {
        NewPumpEvent.suspend(dose: UnfinalizedDose(suspendStartTime: at(start)).toDoseEntry(), date: at(start))
    }

    private func resume(at start: TimeInterval) -> NewPumpEvent {
        NewPumpEvent.resume(dose: UnfinalizedDose(resumeStartTime: at(start), insulinType: .novolog).toDoseEntry(), date: at(start))
    }

    private func ledger(_ batches: [NewPumpEvent]..., replacing: Bool = false) -> ReportedBasalLedger {
        var ledger = ReportedBasalLedger(trackingSince: .distantPast)
        for batch in batches {
            ledger.record(batch, replacePendingEvents: replacing)
        }
        return ledger
    }

    private func rate(_ ledger: ReportedBasalLedger, at seconds: TimeInterval) -> Double {
        ledger.hostBasal(at: at(seconds), schedule: schedule).rate
    }

    // MARK: - The fold

    func testATempBasalCountsUntilItsEnd() {
        let ledger = ledger([temp(1.5, at: 0, endingAt: 600)])

        XCTAssertEqual(rate(ledger, at: -1), 1.0)
        XCTAssertEqual(rate(ledger, at: 0), 1.5)
        XCTAssertEqual(rate(ledger, at: 599), 1.5)
        XCTAssertEqual(rate(ledger, at: 600), 1.0)
        XCTAssertEqual(ledger.hostBasal(at: at(600), schedule: schedule).source, .schedule)
    }

    func testALaterRowCutsAnEarlierOneWhateverTheOrderItArrivedIn() {
        let long = temp(1.5, at: 0, endingAt: 1800)
        let correction = temp(2.2, at: 600, endingAt: 900)

        for ledger in [ledger([long], [correction]), ledger([correction], [long])] {
            XCTAssertEqual(rate(ledger, at: 300), 1.5)
            XCTAssertEqual(rate(ledger, at: 700), 2.2)
            XCTAssertEqual(rate(ledger, at: 1000), 1.0, "the earlier temp basal does not resume after the later row ends")
        }
    }

    func testABasalMarkerReturnsTheHostToItsSchedule() {
        let ledger = ledger([temp(1.5, at: 0)], [temp(1.5, at: 0, endingAt: 300), marker(at: 300)])

        XCTAssertEqual(rate(ledger, at: 400), 1.0)
        XCTAssertEqual(ledger.rows.map(\.kind), [.tempBasal, .basal])
    }

    func testASuspendCountsNothingUntilTheResume() {
        let ledger = ledger([temp(1.5, at: 0, minutes: 60)], [suspend(at: 300)], [resume(at: 900)])

        XCTAssertEqual(ledger.hostBasal(at: at(600), schedule: schedule).source, .suspended)
        XCTAssertEqual(rate(ledger, at: 600), 0)
        XCTAssertEqual(rate(ledger, at: 1000), 1.5, "as Trio's IOB, a temp basal that outlives a suspend runs again after it")
    }

    // MARK: - Matching

    func testAReKeyedReportLandsOnTheRowAtItsDate() {
        let ledger = ledger([temp(1.5, at: 0)], [temp(1.5, at: 0, endingAt: 300, raw: "re-keyed")])

        XCTAssertEqual(ledger.rows.count, 1)
        XCTAssertEqual(ledger.rows.first?.end, at(300))
        XCTAssertEqual(ledger.rows.first?.isMutable, false)
    }

    func testAFinalizedRowNeverChanges() {
        let ledger = ledger([temp(1.5, at: 0, endingAt: 300)], [temp(1.5, at: 0, endingAt: 900)])

        XCTAssertEqual(ledger.rows.first?.end, at(300))
    }

    func testAReplacingBatchDropsTheMutableRowsItLeavesOut() {
        let held = temp(1.5, at: 0)
        let other = suspend(at: 600)

        XCTAssertEqual(ledger([held], [other]).rows.count, 2)
        XCTAssertEqual(ledger([held], [other], replacing: true).rows.map(\.kind), [.suspend])
    }

    func testBolusesAreNotRecorded() {
        let bolus = NewPumpEvent.bolus(
            dose: DoseEntry(type: .bolus, startDate: t0, endDate: t0, value: 1, unit: .units, deliveredUnits: 1),
            date: t0
        )

        XCTAssertTrue(ledger([bolus]).rows.isEmpty)
    }

    // MARK: - Integration

    func testHostUnitsFollowEveryChange() {
        let ledger = ledger([temp(2, at: 100, endingAt: 400)])

        XCTAssertEqual(ledger.hostUnits(in: DateInterval(start: at(0), end: at(600)), schedule: schedule), (100 + 600 + 200) / 3600.0, accuracy: 1e-9)
    }

    func testTheScheduleChangesAtItsSegments() {
        let schedule = HostBasalSchedule(BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .minutes(70), value: 2.0)
        ])!)

        XCTAssertEqual(schedule.rate(at: at(.minutes(59))), 1.0)
        XCTAssertEqual(schedule.rate(at: at(.minutes(61))), 2.0)
        XCTAssertEqual(schedule.changes(in: DateInterval(start: at(0), end: at(.hours(2)))), [at(.minutes(60))])
    }

    // MARK: - Retention and persistence

    func testPruningKeepsTheHeldTempBasal() {
        var ledger = ledger([marker(at: 0), temp(1.5, at: 100)])
        ledger.prune(now: at(ReportedBasalLedger.retention + 200))

        XCTAssertEqual(ledger.rows.map(\.kind), [.tempBasal])
    }

    func testRawValueRoundTrip() {
        var ledger = ledger([temp(1.5, at: 0, endingAt: 300), marker(at: 300), suspend(at: 400), resume(at: 500), temp(0.5, at: 600)])
        ledger.record([temp(0.5, at: 600)], replacePendingEvents: false) { _ in 41 }

        XCTAssertEqual(ReportedBasalLedger(rawValue: ledger.rawValue), ledger)
        XCTAssertEqual(ledger.rows.last?.tempRateId, 41)
    }

    func testTrackingStartsAtTheFirstDecode() {
        let before = Date()
        let state = TandemPumpManagerState(rawValue: [:])
        XCTAssertGreaterThanOrEqual(state.reportedBasal.trackingSince, before)

        let restored = TandemPumpManagerState(rawValue: state.rawValue)
        XCTAssertEqual(restored.reportedBasal.trackingSince, state.reportedBasal.trackingSince)
    }

    // MARK: - Through the manager

    func testEveryEmittedBatchReachesTheLedgerWithTheHeldTempsId() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.basalDose = UnfinalizedDose(tempRate: 1.5, duration: .minutes(30), automatic: true, insulinType: .novolog, startDate: t0, tempRateId: 23)
        let manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())

        manager.emitPumpEvents([NewPumpEvent.tempBasal(dose: state.basalDose.toDoseEntry(isMutable: true, now: t0), date: t0)])

        XCTAssertEqual(manager.state.reportedBasal.rows.map(\.tempRateId), [23])
        XCTAssertEqual(manager.state.reportedBasal.rows.first?.isMutable, true)
    }
}
