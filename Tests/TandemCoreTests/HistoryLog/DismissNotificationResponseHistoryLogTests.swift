@testable import TandemKit
import XCTest

final class DismissNotificationResponseHistoryLogTests: XCTestCase {
    func testDismissNotificationResponseFailedStatus() {
        let expected = DismissNotificationResponseHistoryLog(
            pumpTimeSec: 590519595,
            sequenceNum: 692824,
            responseOpCode: 185,
            status: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4e112b9d322358920a00b9000100000000000000000000000000",
            expected
        )
        XCTAssertEqual(185, parsed.responseOpCode)
        XCTAssertEqual(1, parsed.status)
        XCTAssertEqual(0, parsed.unknown11)
        XCTAssertEqual(Data(count: 13), parsed.unknownTail)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDismissNotificationResponseSuccess() {
        let expected = DismissNotificationResponseHistoryLog(
            pumpTimeSec: 589632874,
            sequenceNum: 646347,
            responseOpCode: 185,
            status: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4e116a152523cbdc0900b9000000000000000000000000000000",
            expected
        )
        XCTAssertEqual(0, parsed.status)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDismissNotificationResponseFailedStatusOfficialApp() {
        let expected = DismissNotificationResponseHistoryLog(
            pumpTimeSec: 539916890,
            sequenceNum: 122665,
            responseOpCode: 185,
            status: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4e115a7a2e2029df0100b9000100000000000000000000000000",
            expected
        )
        XCTAssertEqual(1, parsed.status)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
