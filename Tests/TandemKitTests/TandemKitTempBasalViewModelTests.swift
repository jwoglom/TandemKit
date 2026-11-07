import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitTempBasalViewModelTests: XCTestCase {
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))

    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock(Self.referenceDay.addingTimeInterval(.hours(10)))
    }

    /// 1 U/hr until 14:00 and 2 U/hr after; nothing here talks to the pump.
    private func makeViewModel(maxBasalLimit: Double? = nil) -> TandemKitTempBasalViewModel {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.maxBasalLimitMilliunits = maxBasalLimit.map(TandemPumpCapabilities.milliunits)
        let manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth(), clock: clock)
        return TandemKitTempBasalViewModel(pumpManager: manager)
    }

    private func status(
        percent: Int? = nil,
        isSuspended: Bool = false,
        isLoopTemp: Bool = false,
        isClockSkewCompensation: Bool = false
    ) -> TempRateStatus {
        TempRateStatus(
            percent: percent,
            endDate: percent.map { _ in clock.now.addingTimeInterval(.minutes(30)) },
            profileBasalRate: 1.0,
            currentBasalRate: Double(percent ?? 100) / 100,
            isSuspended: isSuspended,
            isLoopTemp: isLoopTemp,
            isClockSkewCompensation: isClockSkewCompensation
        )
    }

    // MARK: - Which screen

    func testWithNoTempTheFormShows() {
        let viewModel = makeViewModel()

        viewModel.apply(.success(status()))

        XCTAssertEqual(viewModel.screen, .form)
        XCTAssertEqual(viewModel.profileBasalRate, 1.0)
    }

    func testTheLoopsOwnTempAndTheClockSkewTempShowTheForm() {
        let viewModel = makeViewModel()

        viewModel.apply(.success(status(percent: 150, isLoopTemp: true)))
        XCTAssertEqual(viewModel.screen, .form)

        viewModel.apply(.success(status(percent: 90, isClockSkewCompensation: true)))
        XCTAssertEqual(viewModel.screen, .form)
    }

    func testAnyOtherTempShowsTheActiveView() {
        let viewModel = makeViewModel()
        let running = status(percent: 130)

        viewModel.apply(.success(running))

        XCTAssertEqual(viewModel.screen, .active(running))
        XCTAssertEqual(viewModel.title, "Active temp rate")
    }

    func testASuspendedPumpAndNoAnswerHaveScreensOfTheirOwn() {
        let viewModel = makeViewModel()

        viewModel.apply(.success(status(isSuspended: true)))
        XCTAssertEqual(viewModel.screen, .suspended)

        viewModel.apply(.failure(.communication(PumpCommError.noResponse)))
        XCTAssertEqual(viewModel.screen, .unreachable)
    }

    func testTheTitleFollowsTheScreen() {
        let viewModel = makeViewModel()
        var titles: [String] = []
        viewModel.onTitleChange = { titles.append($0) }

        viewModel.apply(.success(status(percent: 130)))
        viewModel.apply(.success(status()))

        XCTAssertEqual(titles, ["Active temp rate", "Temp basal"])
    }

    // MARK: - The form

    func testItStartsAtOneHundredPercentForThirtyMinutesAndCannotSetThat() {
        let viewModel = makeViewModel()
        viewModel.apply(.success(status()))

        XCTAssertEqual(viewModel.percent, 100)
        XCTAssertEqual(viewModel.duration, .minutes(30))
        XCTAssertFalse(viewModel.canSet)

        viewModel.stepUp()
        XCTAssertEqual(viewModel.percent, 110)
        XCTAssertTrue(viewModel.canSet)
    }

    func testTheBoundsFollowTheDuration() {
        clock.set(Self.referenceDay.addingTimeInterval(.hours(14) - .minutes(20)))
        let viewModel = makeViewModel(maxBasalLimit: 3.0)
        viewModel.apply(.success(status()))
        viewModel.percent = 160

        XCTAssertTrue(viewModel.isPercentValid)
        viewModel.hours = 1
        XCTAssertFalse(viewModel.isPercentValid, "160% of 2 U/hr is over the 3 U/hr limit after 14:00")
        XCTAssertEqual(viewModel.percent, 160, "a value outside the bounds is kept")
    }

    func testAProfileChangeInsideTheDurationIsDescribed() {
        clock.set(Self.referenceDay.addingTimeInterval(.hours(14) - .minutes(20)))
        let viewModel = makeViewModel()
        viewModel.apply(.success(status()))
        viewModel.percent = 130

        XCTAssertNil(viewModel.profileChange)
        viewModel.hours = 1
        XCTAssertEqual(viewModel.profileChange?.date, Self.referenceDay.addingTimeInterval(.hours(14)))
        XCTAssertEqual(viewModel.profileChange?.tempRate, 2.6)
    }

    func testATypedRateBecomesTheNearestPercent() {
        let viewModel = makeViewModel()
        viewModel.apply(.success(status()))

        viewModel.setRate(1.234)

        XCTAssertEqual(viewModel.percent, 123)
        XCTAssertEqual(viewModel.rate, 1.23)
    }

    func testTheConfirmationGivesThePercentTheRateAndTheDuration() {
        let viewModel = makeViewModel()
        viewModel.apply(.success(status()))
        viewModel.percent = 130
        viewModel.hours = 1

        XCTAssertEqual(
            viewModel.setConfirmationMessage,
            "Set a temp rate for 130% of profile basal (currently 1.30 U/hr) for a duration of 1 hour, 30 minutes?"
        )
        XCTAssertEqual(viewModel.stopConfirmationMessage(percent: 130), "Stop the active temp rate of 130%?")
    }

    func testATempStartedSinceTheScreenLoadedIsSaidSo() {
        let failure = TandemKitTempBasalViewModel.setFailure(.deviceState(TandemPumpManagerValidationError.tempBasalAlreadyRunning))

        XCTAssertEqual(failure.title, "Could not set temp rate")
        XCTAssertEqual(failure.message, "A temp rate started while you were on this screen.")
    }

    func testOtherFailuresGiveTheDriversReason() {
        let failure = TandemKitTempBasalViewModel.setFailure(.configuration(TandemPumpManagerValidationError.manualTempBasalUnchanged))

        XCTAssertTrue(failure.message.contains("Choose a rate other than 100%."), failure.message)
    }
}
