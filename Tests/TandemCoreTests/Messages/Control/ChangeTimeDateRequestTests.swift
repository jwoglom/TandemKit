import XCTest
@testable import TandemCore

final class ChangeTimeDateRequestTests: XCTestCase {
    private let tandemEpochOffset: TimeInterval = 1199145600

    func testChangeTimeDateRequest_raw() {
        MessageTester.initPumpState("", 0)
        let expected = ChangeTimeDateRequest(cargo: Data([48, 23, 57, 32]))

        let parsed: ChangeTimeDateRequest = MessageTester.test(
            "0143d6431c30173920965d39207d921e9438912a",
            67,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0043998f1154a96aa50bda699dfde690a9"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(540612400, parsed.tandemEpochTime)
        let expectedDate = Date(timeIntervalSince1970: 1739758000)
        let actualDate = Date(timeIntervalSince1970: TimeInterval(parsed.tandemEpochTime) + tandemEpochOffset)
        XCTAssertEqual(expectedDate, actualDate)
    }

    func testChangeTimeDateRequest_asInstant() {
        MessageTester.initPumpState("", 0)
        let instant = Date(timeIntervalSince1970: 1739758000)
        let tandemEpochTime = UInt32(instant.timeIntervalSince1970 - tandemEpochOffset)
        let expected = ChangeTimeDateRequest(tandemEpochTime: tandemEpochTime)

        let parsed: ChangeTimeDateRequest = MessageTester.test(
            "0143d6431c30173920965d39207d921e9438912a",
            67,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0043998f1154a96aa50bda699dfde690a9"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(540612400, parsed.tandemEpochTime)
        let expectedDate = Date(timeIntervalSince1970: 1739758000)
        let actualDate = Date(timeIntervalSince1970: TimeInterval(parsed.tandemEpochTime) + tandemEpochOffset)
        XCTAssertEqual(expectedDate, actualDate)
    }
}
