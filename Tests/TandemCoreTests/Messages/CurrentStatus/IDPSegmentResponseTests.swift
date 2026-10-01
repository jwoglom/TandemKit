@testable import TandemKit
import XCTest

final class IDPSegmentResponseTests: XCTestCase {
    private typealias Status = IDPSegmentResponse.IDPSegmentStatus

    private func assertSegment(
        _ expected: IDPSegmentResponse,
        _ parsed: IDPSegmentResponse,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo, file: file, line: line)
        XCTAssertEqual(expected.idpId, parsed.idpId, "idpId", file: file, line: line)
        XCTAssertEqual(expected.segmentIndex, parsed.segmentIndex, "segmentIndex", file: file, line: line)
        XCTAssertEqual(expected.profileStartTime, parsed.profileStartTime, "profileStartTime", file: file, line: line)
        XCTAssertEqual(expected.profileBasalRate, parsed.profileBasalRate, "profileBasalRate", file: file, line: line)
        XCTAssertEqual(expected.profileCarbRatio, parsed.profileCarbRatio, "profileCarbRatio", file: file, line: line)
        XCTAssertEqual(expected.profileTargetBG, parsed.profileTargetBG, "profileTargetBG", file: file, line: line)
        XCTAssertEqual(expected.profileISF, parsed.profileISF, "profileISF", file: file, line: line)
        XCTAssertEqual(expected.idpStatusId, parsed.idpStatusId, "idpStatusId", file: file, line: line)
    }

    func testIDPSegmentResponse1() {
        let expected = IDPSegmentResponse(
            idpId: 0,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 800,
            profileCarbRatio: 6000,
            profileTargetBG: 120,
            profileISF: 30,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000443040f0000000020037017000078001e000f3078",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
        XCTAssertEqual([.CORRECTION_FACTOR, .TARGET_BG, .CARB_RATIO, .BASAL_RATE], parsed.idpStatus)
    }

    func testIDPSegmentResponse2() {
        let expected = IDPSegmentResponse(
            idpId: 0,
            segmentIndex: 1,
            profileStartTime: 360,
            profileBasalRate: 1250,
            profileCarbRatio: 6000,
            profileTargetBG: 120,
            profileISF: 30,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000543050f00016801e2047017000078001e000f121d",
            5,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
    }

    func testIDPSegmentResponse3() {
        let expected = IDPSegmentResponse(
            idpId: 0,
            segmentIndex: 2,
            profileStartTime: 660,
            profileBasalRate: 1000,
            profileCarbRatio: 6000,
            profileTargetBG: 120,
            profileISF: 30,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000643060f00029402e8037017000078001e000f9460",
            6,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
    }

    func testIDPSegmentResponse4() {
        let expected = IDPSegmentResponse(
            idpId: 0,
            segmentIndex: 3,
            profileStartTime: 720,
            profileBasalRate: 800,
            profileCarbRatio: 6000,
            profileTargetBG: 120,
            profileISF: 30,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000743070f0003d00220037017000078001e000f9b3b",
            7,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
    }

    func testIDPSegmentResponse_Profile1_Midnight_NoBasalOrTargetBg() {
        let expected = IDPSegmentResponse(
            idpId: 1,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 0,
            profileCarbRatio: 99000,
            profileTargetBG: 0,
            profileISF: 99,
            idpStatusId: 11
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000643060f010000000000b8820100000063000bb5d0",
            6,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
        XCTAssertEqual([.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR], parsed.idpStatus)
    }

    func testIDPSegmentResponse_Profile1_Midnight_NoBasal() {
        let expected = IDPSegmentResponse(
            idpId: 1,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 0,
            profileCarbRatio: 99000,
            profileTargetBG: 130,
            profileISF: 99,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000743070f010000000000b8820100820063000f80e6",
            7,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
        XCTAssertEqual([.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR], parsed.idpStatus)
    }

    func testIDPSegmentResponse_Profile1_Midnight_All() {
        let expected = IDPSegmentResponse(
            idpId: 1,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 200,
            profileCarbRatio: 99000,
            profileTargetBG: 130,
            profileISF: 99,
            idpStatusId: 15
        )

        let parsed: IDPSegmentResponse = MessageTester.test(
            "000843080f01000000c800b8820100820063000fcf7c",
            8,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertSegment(expected, parsed)
        XCTAssertEqual([.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR], parsed.idpStatus)
    }

    func testIDPSegmentStatus() {
        XCTAssertEqual(1, Status.BASAL_RATE.rawValue)
        XCTAssertEqual(2, Status.CARB_RATIO.rawValue)
        XCTAssertEqual(4, Status.TARGET_BG.rawValue)
        XCTAssertEqual(8, Status.CORRECTION_FACTOR.rawValue)

        XCTAssertEqual(Status.fromBitmask(1), [.BASAL_RATE])
        XCTAssertEqual(Status.fromBitmask(2), [.CARB_RATIO])
        XCTAssertEqual(Status.fromBitmask(3), [.BASAL_RATE, .CARB_RATIO])
        XCTAssertEqual(Status.fromBitmask(4), [.TARGET_BG])
        XCTAssertEqual(Status.fromBitmask(5), [.TARGET_BG, .BASAL_RATE])
        XCTAssertEqual(Status.fromBitmask(6), [.TARGET_BG, .CARB_RATIO])
        XCTAssertEqual(Status.fromBitmask(7), [.TARGET_BG, .CARB_RATIO, .BASAL_RATE])
    }
}
