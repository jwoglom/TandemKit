@testable import TandemKit
import XCTest

final class ManualTempBasalFormTests: XCTestCase {
    private typealias Form = ManualTempBasalForm

    // MARK: - Valid values

    func testZeroIsAlwaysValidAndNothingElseWithoutAcceptedPercents() {
        XCTAssertTrue(Form.isValid(0, accepted: nil))
        XCTAssertFalse(Form.isValid(50, accepted: nil))
        XCTAssertTrue(Form.isValid(18, accepted: 18 ... 250))
        XCTAssertFalse(Form.isValid(17, accepted: 18 ... 250))
        XCTAssertFalse(Form.isValid(251, accepted: 18 ... 250))
    }

    func testOneHundredPercentCanBeSet() {
        XCTAssertTrue(Form.isValid(100, accepted: 10 ... 250))
        XCTAssertTrue(Form.canSet(100, accepted: 10 ... 250, duration: .minutes(30)))
        XCTAssertTrue(Form.canSet(110, accepted: 10 ... 250, duration: .minutes(30)))
    }

    func testTheDurationRunsFromFifteenMinutesToSeventyTwoHours() {
        XCTAssertFalse(Form.isValid(duration: Form.duration(hours: 0, minutes: 10)))
        XCTAssertTrue(Form.isValid(duration: Form.duration(hours: 0, minutes: 15)))
        XCTAssertTrue(Form.isValid(duration: Form.duration(hours: 72, minutes: 0)))
        XCTAssertFalse(Form.isValid(duration: Form.duration(hours: 72, minutes: 5)))
        XCTAssertFalse(Form.canSet(130, accepted: 10 ... 250, duration: Form.duration(hours: 0, minutes: 10)))
    }

    func testTheDefaultsAreOneHundredPercentForThirtyMinutesInFiveMinuteSteps() {
        XCTAssertEqual(Form.defaultPercent, 100)
        XCTAssertEqual(Form.defaultDuration, .minutes(30))
        XCTAssertEqual(Form.minuteChoices, [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
        XCTAssertEqual(Form.hourChoices.first, 0)
        XCTAssertEqual(Form.hourChoices.last, 72)
    }

    // MARK: - Steppers

    func testStepsGoToTheNextMultipleOfTen() {
        XCTAssertEqual(Form.stepUp(from: 95, accepted: 10 ... 250), 100)
        XCTAssertEqual(Form.stepUp(from: 100, accepted: 10 ... 250), 110)
        XCTAssertEqual(Form.stepDown(from: 95, accepted: 10 ... 250), 90)
        XCTAssertEqual(Form.stepDown(from: 100, accepted: 10 ... 250), 90)
    }

    func testUpFromZeroGoesToTheLowestValidPercent() {
        XCTAssertEqual(Form.stepUp(from: 0, accepted: 1 ... 250), 10)
        XCTAssertEqual(Form.stepUp(from: 0, accepted: 18 ... 250), 18)
    }

    func testDownNeverStepsPastTheLowestValidPercentAndThenGoesToZero() {
        XCTAssertEqual(Form.stepDown(from: 20, accepted: 18 ... 250), 18)
        XCTAssertEqual(Form.stepDown(from: 18, accepted: 18 ... 250), 0)
        XCTAssertEqual(Form.stepDown(from: 5, accepted: 18 ... 250), 0)
    }

    func testEachStepperStopsAtItsEnd() {
        XCTAssertNil(Form.stepDown(from: 0, accepted: 10 ... 250))
        XCTAssertNil(Form.stepUp(from: 250, accepted: 10 ... 250))
        XCTAssertEqual(Form.stepUp(from: 245, accepted: 10 ... 250), 250)
        XCTAssertNil(Form.stepUp(from: 0, accepted: nil))
        XCTAssertEqual(Form.stepDown(from: 30, accepted: nil), 0)
    }

    func testAValueTypedAboveTheRangeStepsDownIntoIt() {
        XCTAssertNil(Form.stepUp(from: 300, accepted: 10 ... 200))
        XCTAssertEqual(Form.stepDown(from: 300, accepted: 10 ... 200), 200)
    }

    // MARK: - The unit view

    func testTheRateIsTheProfilesOnThePumpsGrid() {
        XCTAssertEqual(Form.rate(percent: 130, profileBasalRate: 1.0), 1.3)
        XCTAssertEqual(Form.rate(percent: 124, profileBasalRate: 0.85), 1.05)
        XCTAssertEqual(Form.rate(percent: 0, profileBasalRate: 1.0), 0)
    }

    func testATypedRateIsTheNearestWholePercent() {
        XCTAssertEqual(Form.percent(forRate: 1.05, profileBasalRate: 0.85), 124)
        XCTAssertEqual(Form.percent(forRate: 1.3, profileBasalRate: 1.0), 130)
        XCTAssertNil(Form.percent(forRate: 1.0, profileBasalRate: 0))
        XCTAssertNil(Form.percent(forRate: -1, profileBasalRate: 1.0))
    }
}
