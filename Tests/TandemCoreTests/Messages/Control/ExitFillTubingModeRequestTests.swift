@testable import TandemCore
import XCTest

final class ExitFillTubingModeRequestTests: XCTestCase {
    func testExitFillTubingModeRequest() {
        MessageTester.initPumpState("", 0)
        let expected = ExitFillTubingModeRequest()

        let parsed: ExitFillTubingModeRequest = MessageTester.test(
            "01919691181b0f4120ad6869443532522e06f02a",
            -111,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0091687757e745d1f795a3295f"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
