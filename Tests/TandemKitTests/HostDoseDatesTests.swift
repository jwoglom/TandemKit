import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class HostDoseDatesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func temp(_ rate: Double, from start: Date, to end: Date, isMutable: Bool = false) -> NewPumpEvent {
        let dose = UnfinalizedDose(tempRate: rate, duration: end.timeIntervalSince(start), automatic: true, insulinType: .novolog, startDate: start)
        return NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: isMutable, endDate: end, now: now), of: dose)
    }

    private func bolus(from start: Date, to end: Date) -> NewPumpEvent {
        let dose = DoseEntry(type: .bolus, startDate: start, endDate: end, value: 1, unit: .units, decisionId: nil, deliveredUnits: 1, insulinType: .novolog)
        return NewPumpEvent(date: start, dose: dose, raw: Data([1, 2, 3]), title: "Bolus", type: .bolus)
    }

    func testADoseWithSaneDatesIsLeftAlone() {
        XCTAssertNil(HostDoseDates.repaired(temp(1.0, from: now.addingTimeInterval(-600), to: now), now: now))
        XCTAssertNil(HostDoseDates.repaired(temp(1.0, from: now, to: now.addingTimeInterval(1800), isMutable: true), now: now))
        XCTAssertNil(HostDoseDates.repaired(temp(1.0, from: now.addingTimeInterval(1), to: now.addingTimeInterval(600)), now: now))
    }

    /// The field report's temp basal: dated from a pump stamp an hour ahead, ended at detection.
    func testATempEndingBeforeItStartsIsSentAtItsEndWithNothingDelivered() throws {
        let event = temp(0.42, from: now.addingTimeInterval(.minutes(56)), to: now.addingTimeInterval(-2))

        let (repaired, problem) = try XCTUnwrap(HostDoseDates.repaired(event, now: now))
        let dose = try XCTUnwrap(repaired.dose)

        XCTAssertEqual(dose.startDate, now.addingTimeInterval(-2))
        XCTAssertEqual(dose.endDate, now.addingTimeInterval(-2))
        XCTAssertEqual(dose.unitsPerHour, 0.42, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(dose.deliveredUnits), 0)
        XCTAssertEqual(repaired.raw, event.raw)
        XCTAssertEqual(repaired.date, dose.startDate)
        XCTAssertTrue(problem.contains("ahead of the phone"), problem)
    }

    func testABolusEndingBeforeItStartsEndsWhereItStarts() throws {
        let start = now.addingTimeInterval(-60)

        let dose = try XCTUnwrap(HostDoseDates.repaired(bolus(from: start, to: start.addingTimeInterval(-30)), now: now)?.event.dose)

        XCTAssertEqual(dose.startDate, start)
        XCTAssertEqual(dose.endDate, start)
        XCTAssertEqual(dose.deliveredUnits, 1)
    }

    func testTheManagerNeverSendsTheHostADoseEndingBeforeItStarts() throws {
        let clock = ManualClock(now)
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth(), clock: clock)
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "host-dose-dates-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}

        manager.emitPumpEvents([temp(0.42, from: now.addingTimeInterval(.minutes(56)), to: now.addingTimeInterval(-2))], replacePendingEvents: false)
        queue.sync {}

        let doses = delegate.pumpEvents.compactMap(\.dose)
        XCTAssertEqual(doses.count, 1)
        XCTAssertTrue(doses.allSatisfy { $0.endDate >= $0.startDate && $0.startDate <= self.now }, "\(doses)")
        XCTAssertTrue(manager.state.reportedBasal.rows.allSatisfy { $0.end >= $0.date }, "the ledger holds what the host was sent")
    }
}
