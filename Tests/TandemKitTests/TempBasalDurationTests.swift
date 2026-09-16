import LoopKit
@testable import TandemKit
import XCTest

/// The pump takes a temp rate duration in whole minutes and will not run one shorter than 15
/// minutes, so the driver has to round, bound and report over the duration it actually programmed
/// rather than the one the host asked for (#335).
@available(macOS 13.0, iOS 14.0, *) final class TempBasalDurationTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var queue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 2.0)])!
        manager = TandemPumpManager(state: TandemPumpManagerState(basalRateSchedule: schedule), bluetooth: bluetooth)

        delegate = MockPumpManagerDelegate()
        queue = DispatchQueue(label: "temp-basal-duration-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 2000,
            currentBasalRate: 2000,
            basalModifiedBitmask: 0
        ))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
    }

    override func tearDown() {
        queue = nil
        delegate = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    @discardableResult
    private func enact(unitsPerHour: Double = 1.0, for duration: TimeInterval) -> PumpManagerError? {
        var result: PumpManagerError?
        let completed = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)
        queue.sync {}
        return result
    }

    private var reportedTempBasal: DoseEntry? {
        delegate.pumpEvents.compactMap(\.dose).last(where: { $0.type == .tempBasal })
    }

    // MARK: - Rounding

    /// Truncation turned a whisker under 30 minutes into a 29-minute temp rate.
    func testDurationJustUnderAWholeMinuteRoundsUpInsteadOfTruncating() {
        enact(for: .minutes(30) - 0.4)

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [30])
    }

    func testDurationRoundsToTheNearestMinute() {
        enact(for: .minutes(30) + .seconds(20))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [30])
    }

    /// The dose the host stores has to cover the same span the pump will run, or its
    /// `deliveredUnits` describes insulin that was never scheduled.
    func testTheReportedDoseSpansTheProgrammedMinutesNotTheRequest() throws {
        enact(for: .minutes(30) + .seconds(20))

        let dose = try XCTUnwrap(reportedTempBasal)
        XCTAssertEqual(dose.endDate.timeIntervalSince(dose.startDate), .minutes(30), accuracy: 1.0)
    }

    // MARK: - The pump's minimum

    func testDurationBelowThePumpMinimumIsRefused() throws {
        let error = try XCTUnwrap(enact(for: .minutes(5)))

        guard case let .deviceState(underlying) = error,
              let validation = underlying as? TandemPumpManagerValidationError
        else {
            return XCTFail("Expected a device state validation error, got \(error)")
        }
        XCTAssertEqual(
            validation,
            .tempBasalDurationTooShort(requested: .minutes(5), minimum: .minutes(15))
        )
    }

    /// The refusal happens before any traffic, so a temp rate already running is left alone rather
    /// than stopped with nothing put in its place.
    func testARefusedShortDurationSendsNothingToThePump() {
        enact(for: .minutes(5))

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testExactlyThePumpMinimumIsAccepted() {
        XCTAssertNil(enact(for: .minutes(15)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [15])
    }

    /// A duration that rounds up to the minimum is at the minimum.
    func testADurationThatRoundsUpToTheMinimumIsAccepted() {
        XCTAssertNil(enact(for: .minutes(15) - 0.4))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [15])
    }

    /// A zero duration is a cancel, not a temp rate, so the minimum does not apply to it.
    func testZeroDurationStillCancels() {
        XCTAssertNil(enact(for: 0))

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    // MARK: - The pump's maximum

    /// 72 hours is the ceiling; past it `SetTempRateRequest` would also overflow its millisecond
    /// field.
    func testDurationAboveThePumpMaximumIsClamped() {
        XCTAssertNil(enact(for: .hours(100)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [72 * 60])
    }
}
