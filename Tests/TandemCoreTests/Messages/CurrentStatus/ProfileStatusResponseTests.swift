@testable import TandemKit
import XCTest

final class ProfileStatusResponseTests: XCTestCase {
    func testProfileStatusResponse() {
        let expected = ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: 0,
            idpSlot1Id: -1,
            idpSlot2Id: -1,
            idpSlot3Id: -1,
            idpSlot4Id: -1,
            idpSlot5Id: -1,
            activeSegmentIndex: 3
        )

        let parsed: ProfileStatusResponse = MessageTester.test(
            "00033f03080100ffffffffff03d4c6",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfProfiles)
        XCTAssertEqual(0, parsed.idpSlot0Id)
        XCTAssertEqual(0xFF, parsed.idpSlot1Id)
        XCTAssertEqual(0xFF, parsed.idpSlot2Id)
        XCTAssertEqual(0xFF, parsed.idpSlot3Id)
        XCTAssertEqual(0xFF, parsed.idpSlot4Id)
        XCTAssertEqual(0xFF, parsed.idpSlot5Id)
        XCTAssertEqual(3, parsed.activeSegmentIndex)
    }

    func testProfileStatusResponse_twoProfiles() {
        let expected = ProfileStatusResponse(
            numberOfProfiles: 2,
            idpSlot0Id: 0,
            idpSlot1Id: 1,
            idpSlot2Id: -1,
            idpSlot3Id: -1,
            idpSlot4Id: -1,
            idpSlot5Id: -1,
            activeSegmentIndex: 3
        )

        let parsed: ProfileStatusResponse = MessageTester.test(
            "00043f0408020001ffffffff034403",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.numberOfProfiles)
        XCTAssertEqual(0, parsed.idpSlot0Id)
        XCTAssertEqual(1, parsed.idpSlot1Id)
        XCTAssertEqual(0xFF, parsed.idpSlot2Id)
        XCTAssertEqual(0xFF, parsed.idpSlot3Id)
        XCTAssertEqual(0xFF, parsed.idpSlot4Id)
        XCTAssertEqual(0xFF, parsed.idpSlot5Id)
        XCTAssertEqual(3, parsed.activeSegmentIndex)
    }

    func testProfileStatusResponse_twoProfiles_secondActive() {
        let expected = ProfileStatusResponse(
            numberOfProfiles: 2,
            idpSlot0Id: 1,
            idpSlot1Id: 0,
            idpSlot2Id: -1,
            idpSlot3Id: -1,
            idpSlot4Id: -1,
            idpSlot5Id: -1,
            activeSegmentIndex: 1
        )

        let parsed: ProfileStatusResponse = MessageTester.test(
            "00113f1108020100ffffffff012188",
            17,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.numberOfProfiles)
        XCTAssertEqual(1, parsed.idpSlot0Id)
        XCTAssertEqual(0, parsed.idpSlot1Id)
        XCTAssertEqual(0xFF, parsed.idpSlot2Id)
        XCTAssertEqual(0xFF, parsed.idpSlot3Id)
        XCTAssertEqual(0xFF, parsed.idpSlot4Id)
        XCTAssertEqual(0xFF, parsed.idpSlot5Id)
        XCTAssertEqual(1, parsed.activeSegmentIndex)
    }
}
