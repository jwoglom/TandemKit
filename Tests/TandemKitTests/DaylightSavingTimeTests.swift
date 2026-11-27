import LoopKit
@testable import TandemKit
import XCTest

/// The phone on US Eastern time the day daylight time ends, 1 November 2026 (06:00 UTC: 02:00 EDT
/// back to 01:00 EST). The driver decodes pump times with the phone's offset at the real present, not
/// the test clock's, so each test fixes the pump's wall clock through `pumpTimeCheckUTCOffset`.
@available(macOS 13.0, iOS 14.0, *) final class DaylightSavingTimeTests: XCTestCase {
    private static let standardOffset = -5 * 3600
    private static let daylightOffset = -4 * 3600

    private var originalTZ: String?
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalTZ = ProcessInfo.processInfo.environment["TZ"]
        try phoneZone("America/New_York")

        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.utc(11, 1, 10, 2))
        var state = TandemPumpManagerState(rawValue: [:])
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.5),
            RepeatingScheduleValue(startTime: .hours(6), value: 0.7),
            RepeatingScheduleValue(startTime: .hours(8), value: 0.55),
            RepeatingScheduleValue(startTime: .hours(11), value: 0.55)
        ])!
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
    }

    override func tearDown() {
        manager = nil
        clock = nil
        bluetooth = nil
        if let originalTZ {
            setenv("TZ", originalTZ, 1)
        } else {
            unsetenv("TZ")
        }
        NSTimeZone.resetSystemTimeZone()
        super.tearDown()
    }

    /// `TZ`, since `NSTimeZone.default` does not reach `TimeZone.current` on Linux.
    private func phoneZone(_ identifier: String) throws {
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
        try XCTSkipUnless(TimeZone.current.identifier == identifier, "the phone's zone could not be set to \(identifier)")
    }

    private static func utc(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// The pump's clock reads local time at `utcOffset`, as last read now.
    private func pumpClock(onLocalTimeAt utcOffset: Int) {
        let phoneOffset = TimeZone.current.secondsFromGMT()
        manager.state.lastPumpTimeCheckDate = clock.now
        manager.state.pumpTimeCheckUTCOffset = phoneOffset
        manager.state.currentPumpTime = clock.now.addingTimeInterval(TimeInterval(utcOffset - phoneOffset))
    }

    private func reading(profileRate: Double) -> CurrentBasalStatusResponse {
        let milliunits = UInt32((profileRate * 1000).rounded())
        return CurrentBasalStatusResponse(profileBasalRate: milliunits, currentBasalRate: milliunits, basalModifiedBitmask: 0)
    }

    private func temp(percent: Int, from start: Date) -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: 0.5 * Double(percent) / 100,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: start,
            tempRateId: 7,
            tempPercent: percent
        )
    }

    // MARK: - The schedules' one fixed offset

    private func scheduleZone(_ utcOffset: Int) {
        manager.state.basalRateSchedule.timeZone = TimeZone(secondsFromGMT: utcOffset)!
    }

    func testLoopsScheduleStaysOnTheFixedOffsetAcrossTheDSTChange() {
        manager.hostApp = .loop
        scheduleZone(Self.daylightOffset)

        XCTAssertEqual(manager.getScheduledBasalRate(at: Self.utc(11, 1, 9, 50)), 0.5, "05:50 EDT")
        XCTAssertEqual(manager.getScheduledBasalRate(at: Self.utc(11, 1, 10, 2)), 0.7, "06:02 on the fixed offset, 05:02 EST")
    }

    func testTriosScheduleFollowsThePhonesWallClock() {
        manager.hostApp = .trio
        scheduleZone(Self.daylightOffset)

        XCTAssertEqual(manager.getScheduledBasalRate(at: Self.utc(11, 1, 10, 2)), 0.5, "05:02 EST")
        XCTAssertEqual(manager.getScheduledBasalRate(at: Self.utc(11, 1, 11, 2)), 0.7, "06:02 EST")
    }

    func testTheStatusReportsTheFixedOffset() {
        scheduleZone(Self.daylightOffset)

        XCTAssertEqual(manager.status.timeZone, TimeZone(secondsFromGMT: Self.daylightOffset))
    }

    func testTheDefaultBasalDoseRunsOnTheScheduleZone() {
        scheduleZone(Self.daylightOffset)
        let dose = UnfinalizedDose.defaultBasalDose(
            basalSchedule: manager.state.basalRateSchedule,
            insulineType: .novolog,
            now: Self.utc(11, 1, 10, 2)
        )

        XCTAssertEqual(dose.value, 0.7)
    }

    func testASavedNamedZoneComesBackAsTheFixedOffset() throws {
        var raw = manager.state.rawValue
        var schedule = try XCTUnwrap(raw["basalRateSchedule"] as? [String: Any])
        schedule["timeZoneIdentifier"] = "America/New_York"
        raw["basalRateSchedule"] = schedule

        let zone = try XCTUnwrap(TandemPumpManagerState(rawValue: raw)).scheduleTimeZone
        XCTAssertEqual(zone, TimeZone(secondsFromGMT: TimeZone(identifier: "America/New_York")!.secondsFromGMT()))
    }

    func testAFixedZoneLeavesOutClockDrift() {
        XCTAssertEqual(TandemPumpManagerState.fixedTimeZone(secondsFromGMT: TimeInterval(Self.standardOffset) + 200), TimeZone(secondsFromGMT: Self.standardOffset))
        XCTAssertEqual(TandemPumpManagerState.fixedTimeZone(secondsFromGMT: 5.5 * 3600 - 90), TimeZone(secondsFromGMT: 19800))
    }

    // MARK: - The schedule on the pump's clock

    /// The field report: the pump, set to standard time, ran its 0.5 U/hr at 05:02 EST, and the driver
    /// took the 06:00 segment's 0.7 for the rate in force and refused temp basals for the hour.
    func testAPumpOnStandardTimeRunsTheSegmentThePhonesClockSays() {
        pumpClock(onLocalTimeAt: Self.standardOffset)

        XCTAssertNil(manager.deliveredBasalRateMismatch(reading(profileRate: 0.5)))
        XCTAssertNotNil(manager.deliveredBasalRateMismatch(reading(profileRate: 0.7)))

        clock.set(Self.utc(11, 1, 11, 2))
        XCTAssertNil(manager.deliveredBasalRateMismatch(reading(profileRate: 0.7)), "06:02 EST")
    }

    func testAPumpStillOnDaylightTimeRunsItsSegmentsAnHourEarly() {
        pumpClock(onLocalTimeAt: Self.daylightOffset)

        XCTAssertNil(manager.deliveredBasalRateMismatch(reading(profileRate: 0.7)), "06:02 on the pump")
        XCTAssertEqual(manager.pumpSegmentChanges(after: Self.utc(11, 1, 9, 55), through: Self.utc(11, 1, 10, 5)).map(\.date), [Self.utc(11, 1, 10)])
    }

    /// The field report: a 250% temp running at 05:00 EST was reported at 250% of the 06:00 segment.
    func testATempIsCutAtTheSixOClockSegmentAndNotAnHourEarlier() {
        pumpClock(onLocalTimeAt: Self.standardOffset)
        let running = temp(percent: 250, from: Self.utc(11, 1, 9, 55))

        XCTAssertTrue(manager.splitAtSegmentChanges(running, through: Self.utc(11, 1, 10, 5)).finished.isEmpty)
        XCTAssertEqual(manager.splitAtSegmentChanges(running, through: Self.utc(11, 1, 10, 5)).running.value, 1.25)

        let later = temp(percent: 250, from: Self.utc(11, 1, 10, 55))
        let (finished, after) = manager.splitAtSegmentChanges(later, through: Self.utc(11, 1, 11, 5))
        XCTAssertEqual(finished.compactMap(\.dose?.endDate), [Self.utc(11, 1, 11)])
        XCTAssertEqual(after.value, 1.75)
    }

    // MARK: - Setting the pump's clock

    private func readPumpClock(localTimeAt utcOffset: Int, sinceReset: UInt32) {
        let phoneOffset = TimeZone.current.secondsFromGMT()
        let pumpNow = clock.now.addingTimeInterval(TimeInterval(utcOffset - phoneOffset))
        bluetooth.stub(TimeSinceResetRequest.self, with: TimeSinceResetResponse(
            currentTime: UInt32(Dates.fromInstantToJan12008EpochSeconds(pumpNow)),
            pumpTimeSinceReset: sinceReset
        ))
        manager.fetchTimeSinceReset()
    }

    func testAClockReadFindsThePumpSetBackAnHour() throws {
        clock.set(Self.utc(11, 1, 7, 40))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 1000)
        XCTAssertNil(manager.state.lastPumpClockStep)

        clock.set(Self.utc(11, 1, 7, 48))
        readPumpClock(localTimeAt: Self.standardOffset, sinceReset: 1480)

        let step = try XCTUnwrap(manager.state.lastPumpClockStep)
        XCTAssertEqual(step.by, -.hours(1), accuracy: 1)
        XCTAssertEqual(step.foundAt, Self.utc(11, 1, 7, 48))
    }

    /// Fixed-offset zones either side of the change, since the decode reads the offset at the real present.
    func testThePhoneFallingBackIsNoStepOfThePumpsClock() throws {
        try phoneZone("Etc/GMT+4")
        clock.set(Self.utc(11, 1, 5, 40))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 1000)
        XCTAssertEqual(manager.state.pumpClockOffset, 0, accuracy: 1)

        try phoneZone("Etc/GMT+5")
        clock.set(Self.utc(11, 1, 6, 20))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 3400)

        XCTAssertEqual(manager.state.pumpClockOffset, .hours(1), accuracy: 1, "the pump reads daylight time")
        XCTAssertNil(manager.state.lastPumpClockStep)
    }

    func testAnotherPumpsClockIsNoStep() {
        clock.set(Self.utc(11, 1, 7, 40))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 900_000)

        clock.set(Self.utc(11, 1, 7, 48))
        readPumpClock(localTimeAt: Self.standardOffset, sinceReset: 1000)

        XCTAssertNil(manager.state.lastPumpClockStep)
    }

    func testTheScheduleZoneMovesWhenThePumpsClockIsSetAndNotWhenThePhoneFallsBack() throws {
        try phoneZone("Etc/GMT+4")
        scheduleZone(Self.daylightOffset)
        clock.set(Self.utc(11, 1, 5, 40))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 1000)
        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.daylightOffset))

        try phoneZone("Etc/GMT+5")
        clock.set(Self.utc(11, 1, 6, 20))
        readPumpClock(localTimeAt: Self.daylightOffset, sinceReset: 3400)
        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.daylightOffset), "the pump still reads daylight time")

        clock.set(Self.utc(11, 1, 6, 30))
        readPumpClock(localTimeAt: Self.standardOffset, sinceReset: 4000)
        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.standardOffset))
        XCTAssertEqual(manager.status.timeZone, TimeZone(secondsFromGMT: Self.standardOffset))
    }

    func testAnUntrustedPumpClockLeavesTheScheduleZone() {
        scheduleZone(Self.standardOffset)
        readPumpClock(localTimeAt: Self.standardOffset, sinceReset: 1000)
        clock.set(Self.utc(11, 1, 10, 10))
        readPumpClock(localTimeAt: Self.standardOffset + 3 * 86400, sinceReset: 1480)

        XCTAssertNotNil(manager.state.lastPumpClockStep)
        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.standardOffset))
    }

    /// The skewed clock H6 runs: drift, not a set, so the clock skew temp covers it.
    func testAPumpClockElevenMinutesAheadLeavesTheScheduleZone() {
        scheduleZone(Self.standardOffset)
        readPumpClock(localTimeAt: Self.standardOffset + 11 * 60, sinceReset: 1000)
        clock.set(Self.utc(11, 1, 10, 10))
        readPumpClock(localTimeAt: Self.standardOffset + 11 * 60, sinceReset: 1480)

        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.standardOffset))
    }

    func testAPumpClockSetElevenMinutesAheadLeavesTheScheduleZone() {
        scheduleZone(Self.standardOffset)
        readPumpClock(localTimeAt: Self.standardOffset, sinceReset: 1000)
        clock.set(Self.utc(11, 1, 10, 10))
        readPumpClock(localTimeAt: Self.standardOffset + 11 * 60, sinceReset: 1480)

        XCTAssertNotNil(manager.state.lastPumpClockStep)
        XCTAssertEqual(manager.state.scheduleTimeZone, TimeZone(secondsFromGMT: Self.standardOffset))
    }
}
