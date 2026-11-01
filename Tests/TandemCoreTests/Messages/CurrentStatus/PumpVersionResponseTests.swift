@testable import TandemKit
import XCTest

final class PumpVersionResponseTests: XCTestCase {
    func testPumpVersionResponse() {
        let expected = PumpVersionResponse(
            armSwVer: 105_900,
            mspSwVer: 105_900,
            configABits: 0,
            configBBits: 0,
            serialNum: 90_556_643,
            partNum: 1_005_279,
            pumpRev: "0",
            pcbaSN: 1_088_111_696,
            pcbaRev: "A",
            modelNum: 1_000_354
        )

        let parsed: PumpVersionResponse = MessageTester.test(
            "0003550330ac9d0100ac9d01000000000000000000e3c86505df560f0030000000000000005044db404100000000000000a2430f008722",
            3,
            3,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(parsed.armSwVer, 105_900)
        XCTAssertEqual(parsed.partNum, 1_005_279)
        XCTAssertEqual(parsed.pcbaRev, "A")
        XCTAssertEqual(parsed.modelNum, 1_000_354)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
