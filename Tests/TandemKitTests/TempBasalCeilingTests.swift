import LoopKit
@testable import TandemKit
import XCTest

final class TempBasalCeilingTests: XCTestCase {
    private func schedule(_ items: [(hour: Double, rate: Double)]) -> BasalRateSchedule {
        BasalRateSchedule(dailyItems: items.map { RepeatingScheduleValue(startTime: .hours($0.hour), value: $0.rate) })!
    }

    func testAMaxBasalWithinTwoAndAHalfTimesEverySegmentIsNotCapped() {
        let schedule = schedule([(0, 1.0), (6, 1.5), (22, 1.2)])

        XCTAssertNil(TempBasalCeiling(schedule: schedule, maxBasal: 2.5))
        XCTAssertNil(TempBasalCeiling(schedule: schedule, maxBasal: 2.504), "2.504 U/hr rounds to 250%")
    }

    func testOnlyTheSegmentsTheMaxBasalExceedsAreCapped() throws {
        let schedule = schedule([(0, 0.8), (6, 1.5), (22, 1.0)])

        let ceiling = try XCTUnwrap(TempBasalCeiling(schedule: schedule, maxBasal: 3.0))

        XCTAssertEqual(ceiling.maxBasal, 3.0)
        XCTAssertEqual(ceiling.cappedSegments.map(\.startTime), [.hours(0), .hours(22)])
        XCTAssertEqual(ceiling.cappedSegments.map(\.endTime), [.hours(6), .hours(24)])
        XCTAssertEqual(ceiling.cappedSegments.map(\.scheduledRate), [0.8, 1.0])
        XCTAssertEqual(ceiling.cappedSegments[0].ceiling, 2.0, accuracy: 1e-9)
        XCTAssertEqual(ceiling.cappedSegments[1].ceiling, 2.5, accuracy: 1e-9)
    }

    func testAZeroRateSegmentIsCappedAtZero() throws {
        let ceiling = try XCTUnwrap(TempBasalCeiling(schedule: schedule([(0, 0), (8, 1.0)]), maxBasal: 2.0))

        XCTAssertEqual(ceiling.cappedSegments.map(\.startTime), [.hours(0)])
        XCTAssertEqual(ceiling.cappedSegments[0].ceiling, 0)
    }

    func testNoMaxBasalOrThePlaceholderScheduleIsNotCapped() {
        XCTAssertNil(TempBasalCeiling(schedule: schedule([(0, 1.0)]), maxBasal: nil))
        XCTAssertNil(TempBasalCeiling(schedule: schedule([(0, 1.0)]), maxBasal: 0))
        XCTAssertNil(TempBasalCeiling(schedule: schedule([(0, 0)]), maxBasal: 5.0))
    }

    func testTheManagerReadsTheHostsScheduleAndMaxBasal() throws {
        let unsynced = TandemPumpManager(state: TandemPumpManagerState(basalRateSchedule: schedule([(0, 1.0)])), bluetooth: StubPumpBluetooth())
        XCTAssertNil(unsynced.tempBasalCeiling)

        let manager = TandemPumpManager(
            state: TandemPumpManagerState(basalRateSchedule: schedule([(0, 1.0)]), maxBasalRateUnitsPerHour: 4.0),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertEqual(try XCTUnwrap(manager.tempBasalCeiling).cappedSegments.map(\.ceiling), [2.5])
    }
}
