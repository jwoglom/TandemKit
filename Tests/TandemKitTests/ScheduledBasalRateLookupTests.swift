import LoopKit
@testable import TandemKit
import XCTest

/// The host schedule is looked up at the moment a dose starts, and a segment owns the instant its
/// start time names (#335).
@available(macOS 13.0, iOS 14.0, *) final class ScheduledBasalRateLookupTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(_ items: [(TimeInterval, Double)]) -> TandemPumpManager {
        let schedule = BasalRateSchedule(
            dailyItems: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }
        )!
        return TandemPumpManager(state: TandemPumpManagerState(basalRateSchedule: schedule), bluetooth: bluetooth)
    }

    /// A fixed day, so no assertion here depends on when the suite runs. The schedule repeats
    /// daily and the lookup works in time-of-day, so which day it is does not matter — only that
    /// it is not `Date.now`.
    private let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_718_452_800))

    // MARK: - Segment boundaries

    func testASegmentOwnsTheInstantItStartsAt() {
        let manager = makeManager([(0, 1.0), (.hours(8), 2.0), (.hours(20), 3.0)])

        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight.addingTimeInterval(.hours(8) - 1)), 1.0)
        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight.addingTimeInterval(.hours(8))), 2.0)
        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight.addingTimeInterval(.hours(8) + 1)), 2.0)
    }

    func testTheRateIsTakenFromTheSegmentContainingTheDate() {
        let manager = makeManager([(0, 1.0), (.hours(8), 2.0), (.hours(20), 3.0)])

        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight), 1.0)
        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight.addingTimeInterval(.hours(12))), 2.0)
        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight.addingTimeInterval(.hours(23))), 3.0)
    }

    func testAnEmptyScheduleHasNoRate() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        XCTAssertEqual(manager.getScheduledBasalRate(at: midnight), 0)
    }

    // MARK: - The basal marker after a temp basal expires

    /// A temp basal pinned to a fixed span, so nothing about these assertions depends on the time
    /// the test happens to run at.
    private func expiredTempBasal(endingAt end: Date) -> UnfinalizedDose {
        UnfinalizedDose(rawValue: [
            "type": DoseType.tempBasal.rawValue,
            "value": 2.0,
            "startDate": end.addingTimeInterval(-.minutes(30)),
            "estimatedEndDate": end,
            "deliveredUnits": 0.0,
            "automatic": true,
        ])!
    }

    /// One-minute segments either side of 08:00, each with a rate of its own, so a lookup at the
    /// wrong instant cannot land on the right rate.
    private var narrowSegmentSchedule: [(TimeInterval, Double)] {
        [(0, 1.0), (.hours(8) - .minutes(1), 5.0), (.hours(8), 3.0), (.hours(8) + .minutes(1), 1.0)]
    }

    /// The marker that closes out an expired temp basal is priced at the segment the temp basal
    /// ended in, not the one the sync that noticed it falls in.
    ///
    /// Both ends are checked in one test on purpose: a lookup at any single other instant — the
    /// `Date.now` this used to use among them — gives the same rate for both, so it cannot satisfy
    /// both assertions whenever the test happens to run.
    func testTheBasalMarkerIsPricedAtTheDosesOwnEnd() throws {
        for (offset, expected) in [(-TimeInterval.seconds(30), 5.0), (.seconds(30), 3.0)] {
            let manager = makeManager(narrowSegmentSchedule)
            let tempEnd = midnight.addingTimeInterval(.hours(8) + offset)
            manager.state.basalDose = expiredTempBasal(endingAt: tempEnd)

            let events = manager.getActivePumpEvents(endDate: tempEnd)

            let basal = try XCTUnwrap(events.compactMap(\.dose).last(where: { $0.type == .basal }))
            XCTAssertEqual(basal.startDate, tempEnd)
            XCTAssertEqual(basal.unitsPerHour, expected, accuracy: 1e-9, "ending at 08:00\(offset)s")
            XCTAssertEqual(manager.state.basalDose.value, expected, accuracy: 1e-9, "ending at 08:00\(offset)s")
        }
    }
}
