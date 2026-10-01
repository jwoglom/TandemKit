@testable import TandemKit
import XCTest

final class TimeSinceResetResponseTests: XCTestCase {
    func testTimeSinceResetResponse1() {
        let expected = TimeSinceResetResponse(currentTime: 446_925_049, pumpTimeSinceReset: 10601)

        let parsed: TimeSinceResetResponse = MessageTester.test(
            "0003370308f988a31a69290000db69",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(446_925_049, parsed.currentTime)
        XCTAssertEqual(10601, parsed.pumpTimeSinceReset)
        XCTAssertEqual(
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-02-28T17:50:49Z"),
            parsed.currentTimeDate
        )
    }

    func testTimeSinceResetResponse2() {
        let expected = TimeSinceResetResponse(currentTime: 446_925_437, pumpTimeSinceReset: 10989)

        let parsed: TimeSinceResetResponse = MessageTester.test(
            "00043704087d8aa31aed2a0000b7a9",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(446_925_437, parsed.currentTime)
        XCTAssertEqual(10989, parsed.pumpTimeSinceReset)
    }
}
