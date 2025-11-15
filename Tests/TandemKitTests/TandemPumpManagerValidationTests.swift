import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerValidationTests: XCTestCase {
    func testEnactBolusExceedsMaxBolus() {
        var state = TandemPumpManagerState(
            pumpState: nil,
            settings: TandemPumpManagerSettings(maxBolus: 5.0)
        )

        let manager = TandemPumpManager(state: state)

        let expectation = expectation(description: "Bolus completion")
        manager.enactBolus(units: 6.0, activationType: .manualNoRecommendation) { error in
            guard case let .deviceState(underlyingError?) = error,
                  let validationError = underlyingError as? TandemPumpManagerValidationError
            else {
                XCTFail("Expected deviceState validation error, received: \(String(describing: error))")
                expectation.fulfill()
                return
            }

            XCTAssertEqual(
                validationError,
                .maximumBolusExceeded(requested: 6.0, maximum: 5.0)
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testEnactBolusRespectsInsulinOnBoardLimit() {
        var state = TandemPumpManagerState(
            pumpState: nil,
            settings: TandemPumpManagerSettings(maxBolus: 10.0, maxInsulinOnBoard: 5.0),
            latestInsulinOnBoard: 4.0
        )

        let manager = TandemPumpManager(state: state)

        let expectation = expectation(description: "IOB validation")
        manager.enactBolus(units: 2.0, activationType: .manualNoRecommendation) { error in
            guard case let .deviceState(underlyingError?) = error,
                  let validationError = underlyingError as? TandemPumpManagerValidationError
            else {
                XCTFail("Expected deviceState validation error, received: \(String(describing: error))")
                expectation.fulfill()
                return
            }

            XCTAssertEqual(
                validationError,
                .insulinOnBoardLimitExceeded(currentIOB: 4.0, requested: 2.0, maximum: 5.0)
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testTempBasalExceedsMaximumRate() {
        let state = TandemPumpManagerState(
            pumpState: nil,
            settings: TandemPumpManagerSettings(maxTempBasalRate: 3.0)
        )

        let manager = TandemPumpManager(state: state)

        let expectation = expectation(description: "Temp basal validation")
        manager.enactTempBasal(unitsPerHour: 3.5, for: TimeInterval(hours: 1.0)) { error in
            guard case let .deviceState(underlyingError?) = error,
                  let validationError = underlyingError as? TandemPumpManagerValidationError
            else {
                XCTFail("Expected deviceState validation error, received: \(String(describing: error))")
                expectation.fulfill()
                return
            }

            XCTAssertEqual(
                validationError,
                .maximumTempBasalRateExceeded(requested: 3.5, maximum: 3.0)
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}

private extension TimeInterval {
    init(hours: Double) {
        self = hours * 60.0 * 60.0
    }
}
