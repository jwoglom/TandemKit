import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class HostDoseDatesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func temp(_ rate: Double, from start: Date, to end: Date, isMutable: Bool = false) -> NewPumpEvent {
        let dose = UnfinalizedDose(tempRate: rate, duration: end.timeIntervalSince(start), automatic: true, insulinType: .novolog, startDate: start)
        return NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: isMutable, endDate: end, now: now), of: dose)
    }

    private func bolus(from start: Date, to end: Date, raw: Data = Data([1, 2, 3])) -> NewPumpEvent {
        let dose = DoseEntry(type: .bolus, startDate: start, endDate: end, value: 1, unit: .units, decisionId: nil, deliveredUnits: 1, insulinType: .novolog)
        return NewPumpEvent(date: start, dose: dose, raw: raw, title: "Bolus", type: .bolus)
    }

    private func makeManager(clock: ManualClock? = nil) -> (TandemPumpManager, MockPumpManagerDelegate, DispatchQueue) {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth(), clock: clock ?? ManualClock(now))
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "host-dose-dates-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return (manager, delegate, queue)
    }

    func testADoseWithSaneDatesIsLeftAlone() throws {
        let events = [
            temp(1.0, from: now.addingTimeInterval(-600), to: now),
            temp(1.0, from: now, to: now.addingTimeInterval(1800), isMutable: true),
            temp(1.0, from: now.addingTimeInterval(1), to: now.addingTimeInterval(600))
        ]
        for event in events {
            XCTAssertNil(HostDoseDates.repaired(event))
            XCTAssertFalse(HostDoseDates.startsAhead(try XCTUnwrap(event.dose), of: now))
        }
    }

    func testATempEndingBeforeItStartsIsSentAtItsEndWithNothingDelivered() throws {
        let event = temp(0.42, from: now.addingTimeInterval(-60), to: now.addingTimeInterval(-120))

        let (repaired, problem) = try XCTUnwrap(HostDoseDates.repaired(event))
        let dose = try XCTUnwrap(repaired.dose)

        XCTAssertEqual(dose.startDate, now.addingTimeInterval(-120))
        XCTAssertEqual(dose.endDate, now.addingTimeInterval(-120))
        XCTAssertEqual(dose.unitsPerHour, 0.42, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(dose.deliveredUnits), 0)
        XCTAssertEqual(repaired.raw, event.raw)
        XCTAssertEqual(repaired.date, dose.startDate)
        XCTAssertTrue(problem.contains("before it starts"), problem)
    }

    func testABolusEndingBeforeItStartsEndsWhereItStarts() throws {
        let start = now.addingTimeInterval(-60)

        let dose = try XCTUnwrap(HostDoseDates.repaired(bolus(from: start, to: start.addingTimeInterval(-30)))?.event.dose)

        XCTAssertEqual(dose.startDate, start)
        XCTAssertEqual(dose.endDate, start)
        XCTAssertEqual(dose.deliveredUnits, 1)
    }

    func testTheManagerNeverSendsTheHostADoseEndingBeforeItStarts() throws {
        let (manager, delegate, queue) = makeManager()

        manager.emitPumpEvents([temp(0.42, from: now.addingTimeInterval(-60), to: now.addingTimeInterval(-120))], replacePendingEvents: false)
        queue.sync {}

        let doses = delegate.pumpEvents.compactMap(\.dose)
        XCTAssertEqual(doses.count, 1)
        XCTAssertTrue(doses.allSatisfy { $0.endDate >= $0.startDate }, "\(doses)")
        XCTAssertTrue(manager.state.reportedBasal.rows.allSatisfy { $0.end >= $0.date }, "the ledger holds what the host was sent")
    }

    func testADoseStartingAheadOfThePhoneIsRefusedNotDatedNow() throws {
        let (manager, delegate, queue) = makeManager()
        let yearsAhead = bolus(from: now.addingTimeInterval(.hours(24 * 2512)), to: now.addingTimeInterval(.hours(24 * 2512) + 60), raw: Data([4, 5, 6]))
        let sane = bolus(from: now.addingTimeInterval(-300), to: now.addingTimeInterval(-240))

        manager.emitPumpEvents([
            yearsAhead,
            temp(0.42, from: now.addingTimeInterval(.minutes(56)), to: now.addingTimeInterval(-2)),
            sane
        ], replacePendingEvents: false)
        queue.sync {}

        XCTAssertEqual(delegate.pumpEvents.map(\.raw), [sane.raw])
        XCTAssertTrue(manager.state.reportedBasal.rows.isEmpty, "the ledger holds only what the host was sent")
        XCTAssertEqual(manager.state.futureDatedDoseRefusals.count, 2)
        XCTAssertEqual(manager.state.futureDatedDoseRefusals.lastAt, now)
    }

    func testADoseRefusedOnEveryBatchIsCountedOnce() {
        let (manager, _, queue) = makeManager()
        let ahead = bolus(from: now.addingTimeInterval(.hours(2)), to: now.addingTimeInterval(.hours(2) + 60))

        manager.emitPumpEvents([ahead], replacePendingEvents: false)
        manager.emitPumpEvents([ahead], replacePendingEvents: false)
        queue.sync {}

        XCTAssertEqual(manager.state.futureDatedDoseRefusals.count, 1)
    }

    func testARefusedDoseStaysRefusedOnceThePhoneCatchesUpWithItsDate() {
        let clock = ManualClock(now)
        let (manager, delegate, queue) = makeManager(clock: clock)
        let ahead = bolus(from: now.addingTimeInterval(.hours(2)), to: now.addingTimeInterval(.hours(2) + 60))

        manager.emitPumpEvents([ahead], replacePendingEvents: false)
        clock.advance(by: .hours(3))
        manager.emitPumpEvents([ahead], replacePendingEvents: false)
        queue.sync {}

        XCTAssertTrue(delegate.pumpEvents.isEmpty)
        XCTAssertEqual(manager.state.futureDatedDoseRefusals.count, 1)
    }

    func testARefusalIsForgottenOnceItsStartIsPastTheHistoryFloor() {
        var refusals = FutureDatedDoseRefusals()
        let start = now.addingTimeInterval(.hours(2))
        XCTAssertTrue(refusals.record(raw: Data([7]), startDate: start, at: now))

        XCTAssertTrue(refusals.contains(Data([7]), now: start.addingTimeInterval(BolusReportLedger.retention)))
        XCTAssertFalse(refusals.contains(Data([7]), now: start.addingTimeInterval(BolusReportLedger.retention + 1)))
    }
}
