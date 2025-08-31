import XCTest
@testable import TandemCore

final class Jpake4KeyConfirmationResponseTests: XCTestCase {
    // ./android-2024-02-29-6char2.csv
    func test167cargo5responseSplit() {
        MessageTester.initPumpState("test", 0)
        let nonce = Data(hexadecimalString: "e3fd32509dfacf47")!
        let reserved = Data(hexadecimalString: "0000000000000000")!
        let hashDigest = Data(hexadecimalString: "d0410856c350ce6b9756e03810c6f99a4a0743160a1fdb0973db2f90bdc9a96a")!
        let expected = Jpake4KeyConfirmationResponse(appInstanceId: 0, nonce: nonce, reserved: reserved, hashDigest: hashDigest)

        let parsed: Jpake4KeyConfirmationResponse = MessageTester.test(
            "00042904320000e3fd32509dfacf470000000000000000d0410856c350ce6b9756e03810c6f99a4a0743160a1fdb0973db2f90bdc9a96ad742",
            4,
            4,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.nonce, parsed.nonce)
        MessageTester.assertHexEquals(expected.reserved, parsed.reserved)
        MessageTester.assertHexEquals(expected.hashDigest, parsed.hashDigest)
    }
}
