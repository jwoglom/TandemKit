@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BGHistoryLogTest`.
///
/// The Java test also asserts `getPumpTimeSecInstant()`; there is no equivalent accessor on the
/// Swift `HistoryLog` base class, so the instant is computed directly via
/// `Dates.fromJan12008EpochSecondsToDate`, and the Java test's `Instant` literal is translated
/// from pump wall clock to an instant by `HistoryLogMessageTester.expectedDate(pumpWallClock:)`.
final class BGHistoryLogTests: XCTestCase {
    func testBGHistoryLog() {
        let expected = BGHistoryLog(
            pumpTimeSec: 446061064, sequenceNum: 183533, bg: 162, cgmCalibration: 0, bgSourceId: 1,
            iob: 10.91, targetBG: 110, isf: 30, selectedIOB: 1, bgSourceType: 0, spare: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1000085a961aedcc0200a20000015c8f2e416e001e0001000000",
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(
            Dates.fromJan12008EpochSecondsToDate(TimeInterval(parsed.pumpTimeSec)),
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-02-18T17:51:04Z")
        )
    }
}
