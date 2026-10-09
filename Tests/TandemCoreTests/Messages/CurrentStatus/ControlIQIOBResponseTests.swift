@testable import TandemKit
import XCTest

final class ControlIQIOBResponseTests: XCTestCase {
    func testControlIQIOBResponseNoInsulinOnBoard() {
        let expected = ControlIQIOBResponse(
            mudaliarIOB: 0,
            timeRemainingSeconds: 0,
            mudaliarTotalIOB: 0,
            swan6hrIOB: 0,
            iobType: ControlIQIOBResponse.IOBType.SWAN_6HR.rawValue
        )

        let parsed: ControlIQIOBResponse = MessageTester.test(
            "00036d031100000000000000000000000000000000015aa3",
            3,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.type, .SWAN_6HR)
        XCTAssertEqual(parsed.pumpDisplayedIOB, 0)
    }

    func testControlIQIOBResponseWithControlIQOff() {
        let expected = ControlIQIOBResponse(
            mudaliarIOB: 192,
            timeRemainingSeconds: 14460,
            mudaliarTotalIOB: 241,
            swan6hrIOB: 161,
            iobType: ControlIQIOBResponse.IOBType.MUDALIAR.rawValue
        )

        let parsed: ControlIQIOBResponse = MessageTester.test(
            "00056d0511c00000007c380000f1000000a100000000ab8d",
            5,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.mudaliarIOB, 192)
        XCTAssertEqual(parsed.timeRemainingSeconds, 14460)
        XCTAssertEqual(parsed.mudaliarTotalIOB, 241)
        XCTAssertEqual(parsed.swan6hrIOB, 161)
        XCTAssertEqual(parsed.type, .MUDALIAR)
        XCTAssertEqual(parsed.pumpDisplayedIOB, 192)
    }

    func testControlIQIOBResponseWithControlIQOn() {
        let expected = ControlIQIOBResponse(
            mudaliarIOB: 184,
            timeRemainingSeconds: 14220,
            mudaliarTotalIOB: 241,
            swan6hrIOB: 154,
            iobType: ControlIQIOBResponse.IOBType.SWAN_6HR.rawValue
        )

        let parsed: ControlIQIOBResponse = MessageTester.test(
            "00066d0611b80000008c370000f10000009a00000001c315",
            6,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.mudaliarIOB, 184)
        XCTAssertEqual(parsed.timeRemainingSeconds, 14220)
        XCTAssertEqual(parsed.mudaliarTotalIOB, 241)
        XCTAssertEqual(parsed.swan6hrIOB, 154)
        XCTAssertEqual(parsed.type, .SWAN_6HR)
        XCTAssertEqual(parsed.pumpDisplayedIOB, 154)
    }
}
