@testable import TandemKit
import XCTest

final class HomeScreenMirrorResponseTests: XCTestCase {
    func testHomeScreenMirrorResponse() {
        let expected = HomeScreenMirrorResponse(
            cgmTrendIconId: 0,
            cgmAlertIconId: 255,
            statusIcon0Id: 200,
            statusIcon1Id: 200,
            bolusStatusIconId: 200,
            basalStatusIconId: 4,
            apControlStateIconId: 0,
            remainingInsulinPlusIcon: false,
            cgmDisplayData: false
        )

        let parsed: HomeScreenMirrorResponse = MessageTester.test(
            "000339030900ffc8c8c804000000c1a1",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.noArrow, parsed.cgmTrendIcon)
        XCTAssertEqual(.noError, parsed.cgmAlertIcon)
        XCTAssertEqual(.hide, parsed.statusIcon0)
        XCTAssertEqual(.hide, parsed.statusIcon1)
        XCTAssertEqual(.hide, parsed.bolusStatusIcon)
        XCTAssertEqual(.suspend, parsed.basalStatusIcon)
        XCTAssertEqual(.stateGray, parsed.apControlStateIcon)
        XCTAssertFalse(parsed.remainingInsulinPlusIcon)
        XCTAssertFalse(parsed.cgmDisplayData)
    }
}
