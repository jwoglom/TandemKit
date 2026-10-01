@testable import TandemKit
import XCTest

final class LastBolusStatusV2ResponseTests: XCTestCase {
    func testLastBolusStatusV2ResponseEmpty() {
        let expected = response(0, 0, 0, 0, 0, 0, 0, 0, 0)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0004a504180000000000000000000000000000000000000000000000008521",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
    }

    func testLastBolusStatusV2ResponsePresent() {
        let expected = response(1, 3240, 458_576_820, 6670, 3, 1, 1, 0, 6670)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0004a5041801a80c0000b453551b0e1a0000030101000000000e1a0000b898",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.complete, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2Response05uStopped() {
        let expected = response(1, 3242, 458_586_556, 50, 0, 1, 8, 0, 50)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0007a5071801aa0c0000bc79551b320000000001080000000032000000893b",
            7,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.stopped, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2Response05uCompleted() {
        let expected = response(1, 3243, 458_586_676, 50, 3, 1, 8, 0, 50)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0008a5081801ab0c0000347a551b3200000003010800000000320000001462",
            8,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.complete, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2ResponsePartialStop() {
        let expected = response(1, 3245, 458_594_698, 1975, 0, 1, 8, 0, 2500)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0004a5041801ad0c00008a99551bb707000000010800000000c4090000bc9e",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.stopped, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2ResponseExtendedBolusFirstPartDeliveredSecondInProgress() {
        let expected = response(1, 3248, 458_595_314, 1500, 3, 1, 8, 0, 1500)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0010a5101801b00c0000f29b551bdc05000003010800000000dc050000c546",
            16,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.complete, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2ResponseExtendedBolusAfterStop() {
        let expected = response(1, 3248, 458_595_482, 21, 0, 1, 4, 168, 500)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0016a5161801b00c00009a9c551b15000000000104a8000000f40100003714",
            22,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.stopped, parsed.bolusStatus)
        XCTAssertEqual(.gui, parsed.bolusSource)
    }

    func testLastBolusStatusV2ResponseQuickBolusCancelled() {
        let expected = response(1, 3251, 458_597_185, 500, 0, 0, 1, 0, 500)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0019a5191801b30c000041a3551bf401000000000100000000f4010000afcc",
            25,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.stopped, parsed.bolusStatus)
        XCTAssertEqual(.quickBolus, parsed.bolusSource)
    }

    func testLastBolusStatusV2ResponseControlIQAutoBolus() {
        let expected = response(1, 3274, 458_765_005, 1585, 3, 7, 2, 0, 1585)

        let parsed: LastBolusStatusV2Response = MessageTester.test(
            "0004a5041801ca0c0000cd32581b310600000307020000000031060000a8ca",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertFields(expected, parsed)
        XCTAssertEqual(.complete, parsed.bolusStatus)
        XCTAssertEqual(.controlIQAutoBolus, parsed.bolusSource)
    }

    private func response(
        _ status: Int,
        _ bolusId: Int,
        _ timestamp: UInt32,
        _ deliveredVolume: UInt32,
        _ bolusStatusId: Int,
        _ bolusSourceId: Int,
        _ bolusTypeBitmask: Int,
        _ extendedBolusDuration: UInt32,
        _ requestedVolume: UInt32
    ) -> LastBolusStatusV2Response {
        LastBolusStatusV2Response(
            status: status,
            bolusId: bolusId,
            timestamp: timestamp,
            deliveredVolume: deliveredVolume,
            bolusStatusId: bolusStatusId,
            bolusSourceId: bolusSourceId,
            bolusTypeBitmask: bolusTypeBitmask,
            extendedBolusDuration: extendedBolusDuration,
            requestedVolume: requestedVolume
        )
    }

    private func assertFields(
        _ expected: LastBolusStatusV2Response,
        _ parsed: LastBolusStatusV2Response,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.status, parsed.status, "status", file: file, line: line)
        XCTAssertEqual(expected.bolusId, parsed.bolusId, "bolusId", file: file, line: line)
        XCTAssertEqual(expected.timestamp, parsed.timestamp, "timestamp", file: file, line: line)
        XCTAssertEqual(expected.deliveredVolume, parsed.deliveredVolume, "deliveredVolume", file: file, line: line)
        XCTAssertEqual(expected.bolusStatusId, parsed.bolusStatusId, "bolusStatusId", file: file, line: line)
        XCTAssertEqual(expected.bolusSourceId, parsed.bolusSourceId, "bolusSourceId", file: file, line: line)
        XCTAssertEqual(expected.bolusTypeBitmask, parsed.bolusTypeBitmask, "bolusTypeBitmask", file: file, line: line)
        XCTAssertEqual(
            expected.extendedBolusDuration,
            parsed.extendedBolusDuration,
            "extendedBolusDuration",
            file: file,
            line: line
        )
        XCTAssertEqual(expected.requestedVolume, parsed.requestedVolume, "requestedVolume", file: file, line: line)
    }
}
