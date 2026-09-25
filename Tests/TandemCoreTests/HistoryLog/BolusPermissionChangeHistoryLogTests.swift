@testable import TandemKit
import XCTest

final class BolusPermissionChangeHistoryLogTests: XCTestCase {
    func testMobiBleBolusGranted() {
        let expected = BolusPermissionChangeHistoryLog(
            pumpTimeSec: 589529230, sequenceNum: 640841, bolusId: 2904, unknownU8At12: 1, unknownU8At13: 0, changeReasonId: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("27118e80232349c70900580b0100000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 2904)
        XCTAssertEqual(parsed.unknownU8At12, 1)
        XCTAssertEqual(parsed.changeReason, .GRANTED)
    }

    func testMobiBleBolusReleased() {
        let expected = BolusPermissionChangeHistoryLog(
            pumpTimeSec: 589529231, sequenceNum: 640848, bolusId: 2904, unknownU8At12: 0, unknownU8At13: 1, changeReasonId: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("27118f80232350c70900580b0001010000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At13, 1)
        XCTAssertEqual(parsed.changeReason, .RELEASED)
    }

    // BolusPermissionChangeReasonResponse for this bolus reported lastChangeReasonId 2 in the same capture.
    func testX2BlePermissionRevokedByPumpUi() {
        let expected = BolusPermissionChangeHistoryLog(
            pumpTimeSec: 463684113, sequenceNum: 58319, bolusId: 10681, unknownU8At12: 0, unknownU8At13: 1, changeReasonId: 2
        )

        let parsed = HistoryLogMessageTester.testSingle("27011142a31bcfe30000b9290001020000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.changeReason, .REVOKED_PRIORITY)
    }

    func testX2PumpUiBolusGrantedAndReleased() {
        let granted = BolusPermissionChangeHistoryLog(
            pumpTimeSec: 497746006, sequenceNum: 1903680, bolusId: 9712, unknownU8At12: 3, unknownU8At13: 0, changeReasonId: 0
        )
        let parsedGranted = HistoryLogMessageTester.testSingle("27015600ab1d400c1d00f0250300000000000000000000000000", granted)
        MessageTester.assertHexEquals(granted.cargo, parsedGranted.cargo)

        let released = BolusPermissionChangeHistoryLog(
            pumpTimeSec: 497746007, sequenceNum: 1903682, bolusId: 9712, unknownU8At12: 0, unknownU8At13: 3, changeReasonId: 1
        )
        let parsedReleased = HistoryLogMessageTester.testSingle("27015700ab1d420c1d00f0250003010000000000000000000000", released)
        MessageTester.assertHexEquals(released.cargo, parsedReleased.cargo)
        XCTAssertEqual(parsedReleased.unknownU8At13, parsedGranted.unknownU8At12)
    }
}
