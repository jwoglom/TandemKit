import LoopKit
@testable import TandemKit
import XCTest

/// US Eastern on the 2026 changes: daylight time ends 1 November at 06:00 UTC (02:00 EDT back to
/// 01:00 EST) and begins 8 March at 07:00 UTC (02:00 EST forward to 03:00 EDT).
final class HostBasalScheduleTests: XCTestCase {
    private static let eastern = TimeZone(identifier: "America/New_York")!
    private static let fieldSchedule = BasalRateSchedule(dailyItems: [
        RepeatingScheduleValue(startTime: 0, value: 0.5),
        RepeatingScheduleValue(startTime: .hours(6), value: 0.7),
        RepeatingScheduleValue(startTime: .hours(8), value: 0.55),
        RepeatingScheduleValue(startTime: .hours(11), value: 0.55)
    ])!

    private static func utc(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func eastern(_ schedule: BasalRateSchedule = fieldSchedule) -> HostBasalSchedule {
        HostBasalSchedule(schedule, timeZone: Self.eastern)
    }

    private func schedule(_ items: [(TimeInterval, Double)]) -> BasalRateSchedule {
        BasalRateSchedule(dailyItems: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) })!
    }

    // MARK: - Fall back

    /// The field report: 05:02 EST is 6 h 2 min after midnight EDT, and was read as the 06:00 segment.
    func testOnAFallBackDayTheRateFollowsTheWallClock() {
        let schedule = eastern()

        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 10, 2)), 0.5, "05:02 EST")
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 11, 1)), 0.7, "06:01 EST")
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 12, 59)), 0.7, "07:59 EST")
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 13, 1)), 0.55, "08:01 EST")
    }

    func testOnAFallBackDayTheSegmentsChangeAtTheirWallClockTimes() {
        let day = DateInterval(start: Self.utc(11, 1, 4), end: Self.utc(11, 1, 17))

        XCTAssertEqual(eastern().changes(in: day), [Self.utc(11, 1, 11), Self.utc(11, 1, 13), Self.utc(11, 1, 16)])
    }

    func testAFallBackHourRunsASegmentStartingInsideItTwice() {
        let schedule = eastern(schedule([(0, 1.0), (.minutes(90), 2.0)]))

        XCTAssertEqual(
            schedule.changes(in: DateInterval(start: Self.utc(11, 1, 4), end: Self.utc(11, 1, 8))),
            [Self.utc(11, 1, 5, 30), Self.utc(11, 1, 6), Self.utc(11, 1, 6, 30)],
            "01:30 EDT, back to 01:00 EST, 01:30 EST"
        )
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 5, 45)), 2.0)
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 6, 15)), 1.0)
        XCTAssertEqual(schedule.rate(at: Self.utc(11, 1, 6, 45)), 2.0)
    }

    // MARK: - Spring forward

    func testOnASpringForwardDayTheRateFollowsTheWallClock() {
        let schedule = eastern()

        XCTAssertEqual(schedule.rate(at: Self.utc(3, 8, 9, 30)), 0.5, "05:30 EDT")
        XCTAssertEqual(schedule.rate(at: Self.utc(3, 8, 10, 1)), 0.7, "06:01 EDT")
        XCTAssertEqual(
            schedule.changes(in: DateInterval(start: Self.utc(3, 8, 5), end: Self.utc(3, 8, 17))),
            [Self.utc(3, 8, 10), Self.utc(3, 8, 12), Self.utc(3, 8, 15)]
        )
    }

    func testASegmentStartingInASkippedHourStartsWhenTheClockJumpsPastIt() {
        let schedule = eastern(schedule([(0, 1.0), (.minutes(150), 2.0)]))

        XCTAssertEqual(schedule.changes(in: DateInterval(start: Self.utc(3, 8, 5), end: Self.utc(3, 8, 9))), [Self.utc(3, 8, 7)])
        XCTAssertEqual(schedule.rate(at: Self.utc(3, 8, 6, 59)), 1.0, "01:59 EST")
        XCTAssertEqual(schedule.rate(at: Self.utc(3, 8, 7, 1)), 2.0, "03:01 EDT")
    }

    // MARK: - The pump's clock

    /// A pump left on daylight time, which it keeps until someone sets it.
    func testThePumpsClockKeepsItsOwnTimeOfDayAcrossTheChange() {
        let pump = HostBasalSchedule.pumpClock(Self.fieldSchedule, pumpWallClockShift: -.hours(4))

        XCTAssertEqual(pump.rate(at: Self.utc(11, 1, 10, 2)), 0.7, "06:02 on the pump")
        XCTAssertEqual(pump.secondsSinceMidnight(at: Self.utc(11, 1, 10, 2)), .hours(6) + .minutes(2))
        XCTAssertEqual(
            pump.changes(in: DateInterval(start: Self.utc(11, 1, 4), end: Self.utc(11, 1, 17))),
            [Self.utc(11, 1, 10), Self.utc(11, 1, 12), Self.utc(11, 1, 15)]
        )
    }

    func testOnAnOrdinaryDayBothClocksAgree() {
        let host = eastern()
        let pump = HostBasalSchedule.pumpClock(Self.fieldSchedule, pumpWallClockShift: -.hours(5))
        let day = DateInterval(start: Self.utc(11, 2, 5), end: Self.utc(11, 3, 5))

        XCTAssertEqual(host.changes(in: day), pump.changes(in: day))
        for hour in stride(from: 0.0, to: 24, by: 0.5) {
            let date = day.start.addingTimeInterval(.hours(hour))
            XCTAssertEqual(host.rate(at: date), pump.rate(at: date), "\(date)")
        }
    }
}
