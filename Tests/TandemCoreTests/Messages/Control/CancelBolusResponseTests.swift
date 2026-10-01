@testable import TandemKit
import XCTest

final class CancelBolusResponseTests: XCTestCase {
    func testCancelBolusResponse_ID10677() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_145)
        let expected = CancelBolusResponse(statusId: 0, bolusId: 10677, reasonId: 0)

        let parsed: CancelBolusResponse = MessageTester.test(
            "00bca1bc1d00b52900006923851bda3537a211cbd8ae95fec6d7a2a3d892d8f8af36bdc7",
            -68,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.statusId)
        XCTAssertEqual(10677, parsed.bolusId)
        XCTAssertEqual(0, parsed.reasonId)
        XCTAssertEqual(.success, parsed.status)
        XCTAssertEqual(.noError, parsed.reason)
    }

    func testCancelBolusResponse_ID10678() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_145)
        let expected = CancelBolusResponse(statusId: 0, bolusId: 10678, reasonId: 0)

        let parsed: CancelBolusResponse = MessageTester.test(
            "00e8a1e81d00b62900009e23851b90d69beb26e8071804420d24cee664931b862a875929",
            -24,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.statusId)
        XCTAssertEqual(10678, parsed.bolusId)
        XCTAssertEqual(0, parsed.reasonId)
        XCTAssertEqual(.success, parsed.status)
        XCTAssertEqual(.noError, parsed.reason)
    }

    func testCancelBolusResponse_ID10688_cancelledAfterCompletedDelivery() {
        MessageTester.initPumpState("bJVYJq9jdtjxPcYa", 463_692_320)
        let expected = CancelBolusResponse(statusId: 1, bolusId: 10688, reasonId: 2)

        let parsed: CancelBolusResponse = MessageTester.test(
            "0006a1061d01c02902004e62a31b93f40e8ae917aa40df366dd04d0cdb19d1c0fdd3b4f9",
            6,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.statusId)
        XCTAssertEqual(10688, parsed.bolusId)
        XCTAssertEqual(2, parsed.reasonId)
        XCTAssertEqual(.failed, parsed.status)
        XCTAssertEqual(.invalidOrAlreadyDelivered, parsed.reason)
    }

    func testCancelBolusResponse_invalidId() {
        MessageTester.initPumpState("bJVYJq9jdtjxPcYa", 463_693_031)
        let expected = CancelBolusResponse(statusId: 1, bolusId: 34463, reasonId: 2)

        let parsed: CancelBolusResponse = MessageTester.test(
            "0004a1041d019f8602000f65a31ba24ec318b5b102d56ee0db9463eb4d645ed2b2560905",
            4,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.statusId)
        XCTAssertEqual(34463, parsed.bolusId)
        XCTAssertEqual(2, parsed.reasonId)
        XCTAssertEqual(.failed, parsed.status)
        XCTAssertEqual(.invalidOrAlreadyDelivered, parsed.reason)
    }

    func testCancelBolusResponse_Mobi_extendedbolus() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_413)
        let expected = CancelBolusResponse(statusId: 0, bolusId: 501, reasonId: 0)

        let parsed: CancelBolusResponse = MessageTester.test(
            "002da12d1d00f50100007b428b1e59cc3479f5c851559f897f196f9511a5916f7499ff65",
            45,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.statusId)
        XCTAssertEqual(501, parsed.bolusId)
        XCTAssertEqual(0, parsed.reasonId)
        XCTAssertEqual(.success, parsed.status)
        XCTAssertEqual(.noError, parsed.reason)
    }
}
