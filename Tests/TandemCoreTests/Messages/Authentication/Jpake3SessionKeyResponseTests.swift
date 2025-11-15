@testable import TandemCore
import XCTest

final class Jpake3SessionKeyResponseTests: XCTestCase {
    // ./android-2024-02-29-6char2.csv
    func test167cargo4responseSplit() {
        MessageTester.initPumpState("test", 0)
        let expected = Jpake3SessionKeyResponse(cargo: Data(hexadecimalString: "000002e91fff505adb4f0000000000000000")!)

        let parsed: Jpake3SessionKeyResponse = MessageTester.test(
            "0003270312000002e91fff505adb4f0000000000000000ba54",
            3,
            2,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.deviceKeyNonce, parsed.deviceKeyNonce)
        MessageTester.assertHexEquals(expected.deviceKeyReserved, parsed.deviceKeyReserved)
    }

    // ./android-2024-02-29-6char2.csv
    func test167cargo4responseSplitSeparated() {
        MessageTester.initPumpState("test", 0)
        let nonce = Data(hexadecimalString: "02e91fff505adb4f")!
        let reserved = Data(hexadecimalString: "0000000000000000")!
        let expected = Jpake3SessionKeyResponse(appInstanceId: 0, nonce: nonce, reserved: reserved)

        let parsed: Jpake3SessionKeyResponse = MessageTester.test(
            "0003270312000002e91fff505adb4f0000000000000000ba54",
            3,
            2,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.deviceKeyNonce, parsed.deviceKeyNonce)
        MessageTester.assertHexEquals(expected.deviceKeyReserved, parsed.deviceKeyReserved)
    }
}
