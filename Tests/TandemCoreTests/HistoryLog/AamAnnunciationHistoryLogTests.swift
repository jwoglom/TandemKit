@testable import TandemKit
import XCTest

final class AamAnnunciationHistoryLogTests: XCTestCase {
    func testAamAnnunciationMinBasalAlert() {
        let expected = AamAnnunciationHistoryLog(
            pumpTimeSec: 591099614,
            sequenceNum: 723640,
            categoryId: 3,
            unknown11: 1,
            unknown12: 0,
            notificationId: 26,
            unknown18: 4,
            unknown19: 3
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "b211de763b23b80a0b00030100001a0000000403000000000000",
            expected
        )
        XCTAssertEqual(591099614, parsed.pumpTimeSec)
        XCTAssertEqual(723640, parsed.sequenceNum)
        XCTAssertEqual(.alert, parsed.category)
        XCTAssertEqual(26, parsed.notificationId)
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.MIN_BASAL_ALERT2, parsed.alertResponseType)
        XCTAssertNil(parsed.alarmResponseType)
        XCTAssertEqual(1, parsed.unknown11)
        XCTAssertEqual(0, parsed.unknown12)
        XCTAssertEqual(4, parsed.unknown18)
        XCTAssertEqual(3, parsed.unknown19)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAamAnnunciationLowInsulinAlertIsIdZero() {
        let expected = AamAnnunciationHistoryLog(
            pumpTimeSec: 590177860,
            sequenceNum: 674178,
            categoryId: 3,
            unknown11: 1,
            unknown12: 0,
            notificationId: 0,
            unknown18: 4,
            unknown19: 3
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "b21144662d2382490a0003010000000000000403000000000000",
            expected
        )
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT, parsed.alertResponseType)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAamAnnunciationResumePumpAlarm() {
        let expected = AamAnnunciationHistoryLog(
            pumpTimeSec: 590519377,
            sequenceNum: 692809,
            categoryId: 4,
            unknown11: 3,
            unknown12: 10,
            notificationId: 18,
            unknown18: 6,
            unknown19: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "b211519c322349920a0004030a00120000000600000000000000",
            expected
        )
        XCTAssertEqual(.alarm, parsed.category)
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM, parsed.alarmResponseType)
        XCTAssertNil(parsed.alertResponseType)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAamAnnunciationResumePumpAlarm2() {
        let expected = AamAnnunciationHistoryLog(
            pumpTimeSec: 590930784,
            sequenceNum: 714786,
            categoryId: 4,
            unknown11: 3,
            unknown12: 0,
            notificationId: 23,
            unknown18: 6,
            unknown19: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "b21160e3382322e80a0004030000170000000600000000000000",
            expected
        )
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2, parsed.alarmResponseType)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAamAnnunciationCgmAlertX2() {
        let expected = AamAnnunciationHistoryLog(
            pumpTimeSec: 534250647,
            sequenceNum: 1053230,
            categoryId: 6,
            unknown11: 1,
            unknown12: 40,
            notificationId: 14,
            unknown18: 14,
            unknown19: 3
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "b2019704d81f2e121000060128000e0000000e03000000000000",
            expected
        )
        XCTAssertEqual(.cgmAlert, parsed.category)
        XCTAssertNil(parsed.alertResponseType)
        XCTAssertNil(parsed.alarmResponseType)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAamCategoryUnknownIdIsNil() {
        XCTAssertNil(AamAnnunciationHistoryLog.AamCategory(rawValue: 5))
    }
}
