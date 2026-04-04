@testable import TandemCore
@testable import TandemKit
import XCTest

final class PumpNotificationRouterTests: XCTestCase {
    func testNormalizeQualifyingEventsPrefersBolusChangeOverExtendedBolusChange() {
        XCTAssertEqual(
            Set([QualifyingEvent.alert, .bolusChange]),
            PumpNotificationRouter.normalizeQualifyingEvents([.alert, .bolusChange, .extendedBolusChange])
        )
    }

    func testNormalizeQualifyingEventsPreservesExtendedBolusChangeWhenBolusChangeMissing() {
        XCTAssertEqual(
            Set([QualifyingEvent.alert, .extendedBolusChange]),
            PumpNotificationRouter.normalizeQualifyingEvents([.alert, .extendedBolusChange])
        )
    }
}
