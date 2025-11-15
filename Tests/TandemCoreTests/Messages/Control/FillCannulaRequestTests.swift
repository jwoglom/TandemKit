@testable import TandemCore
import XCTest

final class FillCannulaRequestTests: XCTestCase {
    func testFillCannulaRequest() {
        MessageTester.initPumpState("", 0)
        let expected = FillCannulaRequest(primeSizeMilliUnits: 300)

        let parsed: FillCannulaRequest = MessageTester.test(
            "016d986d1a2c010f152820b9273d0fb99c1241f1",
            109,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "006db9da764426a0aa99bb708571f4"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
