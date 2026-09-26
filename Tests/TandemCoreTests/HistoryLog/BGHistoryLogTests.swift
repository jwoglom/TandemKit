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
        XCTAssertEqual(parsed.bg, 162)
        XCTAssertEqual(parsed.cgmCalibration, 0)
        XCTAssertFalse(parsed.isUsedForCgmCalibration)
        XCTAssertEqual(parsed.bgSource, .cgm)
        XCTAssertEqual(parsed.targetBG, 110)
        XCTAssertEqual(parsed.isf, 30)
        XCTAssertEqual(parsed.selectedIOBType, .swanIOBMeal)
        XCTAssertEqual(parsed.bgSourceTypeEnum, .localPumpEntry)
    }

    // Tandem Mobi, official Tandem app, March 2025 BLE capture: a fingerstick BG of 170 entered in
    // the app and used to calibrate the CGM (a CGM calibration log with the same value was written
    // in the same second). Header high nibble is 1.
    func testBGHistoryLogMobiCalibrationRemoteEntry() {
        let expected = BGHistoryLog(
            pumpTimeSec: 542807876, sequenceNum: 231542, bg: 170, cgmCalibration: 1, bgSourceId: 0,
            iob: Float(bitPattern: 0x415c4199), targetBG: 110, isf: 30, selectedIOB: 1, bgSourceType: 1, spare: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "101044975a2076880300aa00010099415c416e001e0001010000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bg, 170)
        XCTAssertTrue(parsed.isUsedForCgmCalibration)
        XCTAssertEqual(parsed.bgSource, .manual)
        XCTAssertEqual(parsed.selectedIOBType, .swanIOBMeal)
        XCTAssertEqual(parsed.bgSourceTypeEnum, .remoteEntry)
    }

    func testBgSourceTypeRawValues() {
        XCTAssertEqual(BGHistoryLog.BgSourceType(rawValue: 0), .localPumpEntry)
        XCTAssertEqual(BGHistoryLog.BgSourceType(rawValue: 1), .remoteEntry)
        XCTAssertNil(BGHistoryLog.BgSourceType(rawValue: 2))
    }
}
