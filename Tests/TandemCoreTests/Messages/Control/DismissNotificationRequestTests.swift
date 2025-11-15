@testable import TandemCore
import XCTest

final class DismissNotificationRequestTests: XCTestCase {
    func testDismissNotificationRequest_SiteChangeNotification() {
        MessageTester.initPumpState("", 0)
        let expected = DismissNotificationRequest(cargo: Data([2, 0, 0, 0, 0, 0]))
        let parsed: DismissNotificationRequest = MessageTester.test(
            "011eb81e1e02000000000091eef21fb2f51e9b10",
            30,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "001e1923326c7764e514a7cd6e702210fbe0f0"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(UInt32(ReminderStatusResponse.ReminderType.SITE_CHANGE_REMINDER.rawValue), parsed.notificationId)
        XCTAssertEqual(.reminder, parsed.notificationType)
    }

    func testDismissNotificationRequest_alert_CGM_GRAPH_REMOVED() {
        MessageTester.initPumpState("", 0)
        let expected = DismissNotificationRequest(cargo: Data([25, 0, 0, 0, 1, 0]))
        let parsed: DismissNotificationRequest = MessageTester.test(
            "01ddb8dd1e1900000001001b92f41f4ebdd42d94",
            -35,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00dd71575252fcc1476112db4196041031cf27"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(UInt32(AlertStatusResponse.AlertResponseType.CGM_GRAPH_REMOVED.rawValue), parsed.notificationId)
        XCTAssertEqual(.alert, parsed.notificationType)
    }

    func testDismissNotificationRequest_alert_INVALID_TRANSMITTER_ID() {
        MessageTester.initPumpState("", 0)
        let expected = DismissNotificationRequest(cargo: Data([29, 0, 0, 0, 1, 0]))
        let parsed: DismissNotificationRequest = MessageTester.test(
            "0112b8121e1d00000001008190fd1fd4f0eef6a2",
            18,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0012398a829fd5358e41f168f0b82619ad9976"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(UInt32(AlertStatusResponse.AlertResponseType.INVALID_TRANSMITTER_ID.rawValue), parsed.notificationId)
        XCTAssertEqual(.alert, parsed.notificationType)
    }

    func testDismissNotificationRequest_g6CgmSensorFailed() {
        MessageTester.initPumpState("", 0)
        let expected = DismissNotificationRequest(cargo: Data([11, 0, 0, 0, 3, 0]))
        let parsed: DismissNotificationRequest = MessageTester.test(
            "01e9b8e91e0b0000000300de6e392075306d24bb",
            -23,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00e92094d6d88830447aa4c9d10af3196a91a1"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(UInt32(CGMAlertStatusResponse.CGMAlert.SENSOR_FAILED_CGM_ALERT.rawValue), parsed.notificationId)
        XCTAssertEqual(.cgmAlert, parsed.notificationType)
    }

    func testDismissNotificationRequest_pumpResetAlarm() {
        MessageTester.initPumpState("", 0)
        let expected = DismissNotificationRequest(cargo: Data([3, 0, 0, 0, 2, 0]))
        let parsed: DismissNotificationRequest = MessageTester.test(
            "01a6b8a61e03000000020058e93920faf75ae477",
            -90,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00a674346fb57c95916f8fde8e2e79f605dee3"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(UInt32(AlarmStatusResponse.AlarmResponseType.PUMP_RESET_ALARM.rawValue), parsed.notificationId)
        XCTAssertEqual(.alarm, parsed.notificationType)
    }
}
