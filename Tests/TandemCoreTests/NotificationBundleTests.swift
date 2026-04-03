@testable import TandemCore
import XCTest

final class NotificationBundleTests: XCTestCase {
    // MARK: - Helper functions to create bitmasks

    /// Creates a bitmask from the given bit positions (raw values)
    private func bitmask(_ positions: Int...) -> UInt64 {
        positions.reduce(0) { result, position in
            result | (1 << position)
        }
    }

    // MARK: - Count Sync Tests

    /// Verifies that getNotificationCount() always equals get().count
    func testNotificationCountMatchesItemsCount() {
        let bundle = NotificationBundle()

        // Empty bundle
        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
        XCTAssertEqual(bundle.getNotificationCount(), 0)

        // Add some alerts (bits 0 and 5 = LOW_INSULIN_ALERT and AUTO_OFF_ALERT)
        let alertResponse = AlertStatusResponse(intMap: bitmask(0, 5))
        bundle.add(alertResponse)

        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
        XCTAssertEqual(bundle.getNotificationCount(), 2)

        // Add reminders (bits 0 and 1 = LOW_BG_REMINDER and HIGH_BG_REMINDER)
        let reminderResponse = ReminderStatusResponse(intMap: bitmask(0, 1))
        bundle.add(reminderResponse)

        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
        XCTAssertEqual(bundle.getNotificationCount(), 4)

        // Add alarms (bit 2 = OCCLUSION_ALARM)
        let alarmResponse = AlarmStatusResponse(intMap: bitmask(2))
        bundle.add(alarmResponse)

        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
        XCTAssertEqual(bundle.getNotificationCount(), 5)

        // Add CGM alerts (bits 1 and 2 = FIXED_LOW_CGM_ALERT and HIGH_CGM_ALERT)
        let cgmAlertResponse = CGMAlertStatusResponse(intMap: bitmask(1, 2))
        bundle.add(cgmAlertResponse)

        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
        XCTAssertEqual(bundle.getNotificationCount(), 7)
    }

    /// Verifies that isEmpty reflects the actual state
    func testIsEmptyProperty() {
        let bundle = NotificationBundle()

        XCTAssertTrue(bundle.isEmpty)
        XCTAssertEqual(bundle.getNotificationCount(), 0)

        let alertResponse = AlertStatusResponse(intMap: bitmask(0))
        bundle.add(alertResponse)

        XCTAssertFalse(bundle.isEmpty)
        XCTAssertEqual(bundle.getNotificationCount(), 1)
    }

    /// Verifies that malfunction notifications are counted correctly
    func testMalfunctionNotificationCounting() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: 12-0x2071 (stuck vibrator motor), non-ignorable
        let expected = MalfunctionStatusResponse(codeA: 12, codeB: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let malfunctionResponse: MalfunctionStatusResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, malfunctionResponse.cargo)
        XCTAssertEqual(12, malfunctionResponse.codeA)
        XCTAssertEqual(0x2071, malfunctionResponse.codeB)
        bundle.add(malfunctionResponse)

        // Malfunction should be counted since codes are not in IGNORABLE_CODES
        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that ignorable malfunctions are not counted
    func testIgnorableMalfunctionNotCounted() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: 3-0x2026 (ignorable)
        let expected = MalfunctionStatusResponse(codeA: 3, codeB: 0x2026, remaining: Data([2, 0xFF, 0xFF]))
        let malfunctionResponse: MalfunctionStatusResponse = MessageTester.test(
            "001079100b030000002620000002ffff2ab0",
            16,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, malfunctionResponse.cargo)
        XCTAssertEqual(3, malfunctionResponse.codeA)
        XCTAssertEqual(0x2026, malfunctionResponse.codeB)
        bundle.add(malfunctionResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 0)
        XCTAssertEqual(bundle.get().count, 0)
    }

    /// Verifies that malfunction is suppressed when its ID matches an alarm
    func testMalfunctionSuppressedByMatchingAlarm() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: codeA 12, and alarm bit 12 is BATTERY_SHUTDOWN_ALARM (known)
        let alarmResponse = AlarmStatusResponse(intMap: bitmask(12))
        bundle.add(alarmResponse)

        let expected = MalfunctionStatusResponse(codeA: 12, codeB: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let malfunctionResponse: MalfunctionStatusResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(malfunctionResponse)

        // Malfunction should be suppressed because codeA (12) matches BATTERY_SHUTDOWN_ALARM
        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is suppressed when its ID matches a known alert
    func testMalfunctionSuppressedByMatchingKnownAlert() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: codeA 12, and alert bit 12 is a known alert
        bundle.add(AlertStatusResponse(intMap: bitmask(12)))
        let expected = MalfunctionStatusResponse(codeA: 12, codeB: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let malfunctionResponse: MalfunctionStatusResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(malfunctionResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is NOT suppressed by a default/unknown reminder ID
    func testMalfunctionNotSuppressedByDefaultReminder() {
        let bundle = NotificationBundle()

        // PumpX2 comment payload: codeA 23, and reminder bit 23 is DEFAULT_REMINDER_23
        bundle.add(ReminderStatusResponse(intMap: bitmask(23)))
        let expected = MalfunctionStatusResponse(codeA: 23, codeB: 0x20A7, remaining: Data([2, 0xFF, 0xFF]))
        let malfunctionResponse = MalfunctionStatusResponse(cargo: Data(hexadecimalString: "17000000a720000002ffff")!)
        MessageTester.assertHexEquals(expected.cargo, malfunctionResponse.cargo)
        XCTAssertEqual(23, malfunctionResponse.codeA)
        XCTAssertEqual(0x20A7, malfunctionResponse.codeB)
        bundle.add(malfunctionResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 2)
        XCTAssertEqual(bundle.get().count, 2)
    }

    /// Verifies that malfunction is suppressed when its ID matches a known CGM alert
    func testMalfunctionSuppressedByMatchingKnownCGMAlert() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: codeA 12, and CGM alert bit 12 is known
        bundle.add(CGMAlertStatusResponse(intMap: bitmask(12)))
        let expected = MalfunctionStatusResponse(codeA: 12, codeB: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let malfunctionResponse: MalfunctionStatusResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(malfunctionResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is NOT suppressed by a default/unknown CGM alert ID
    func testMalfunctionNotSuppressedByDefaultCGMAlert() {
        let bundle = NotificationBundle()

        // PumpX2 comment payload: codeA 23, and CGM alert bit 23 is DEFAULT_CGM_ALERT_23
        bundle.add(CGMAlertStatusResponse(intMap: bitmask(23)))
        let expected = MalfunctionStatusResponse(codeA: 23, codeB: 0x20A7, remaining: Data([2, 0xFF, 0xFF]))
        let malfunctionResponse = MalfunctionStatusResponse(cargo: Data(hexadecimalString: "17000000a720000002ffff")!)
        MessageTester.assertHexEquals(expected.cargo, malfunctionResponse.cargo)
        XCTAssertEqual(23, malfunctionResponse.codeA)
        XCTAssertEqual(0x20A7, malfunctionResponse.codeB)
        bundle.add(malfunctionResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 2)
        XCTAssertEqual(bundle.get().count, 2)
    }

    /// Verifies alert `notificationIds` excludes default/unknown alert IDs (no matching PumpX2 malfunction payload for a default alert ID in the referenced test file).
    func testAlertNotificationIdsExcludeDefaultAlerts() {
        let response = AlertStatusResponse(intMap: bitmask(21, 22))

        XCTAssertFalse(response.notificationIds.contains(21)) // DEFAULT_ALERT_21
        XCTAssertTrue(response.notificationIds.contains(22)) // SENSOR_EXPIRING_ALERT
    }

    /// Verifies reminder `notificationIds` excludes default/unknown reminder IDs while keeping known IDs.
    func testReminderNotificationIdsExcludeDefaultReminders() {
        let response = ReminderStatusResponse(intMap: bitmask(3, 23))

        XCTAssertTrue(response.notificationIds.contains(3)) // MISSED_MEAL_REMINDER
        XCTAssertFalse(response.notificationIds.contains(23)) // DEFAULT_REMINDER_23
    }

    // MARK: - Response Addition Tests

    func testAddAlertStatusResponse() {
        let bundle = NotificationBundle()
        // bits 0, 5, 17 = LOW_INSULIN_ALERT, AUTO_OFF_ALERT, LOW_INSULIN_ALERT2
        let response = AlertStatusResponse(intMap: bitmask(0, 5, 17))
        bundle.add(response)

        XCTAssertEqual(bundle.getNotificationCount(), 3)
        XCTAssertNotNil(bundle.alertStatusResponse)
        XCTAssertEqual(bundle.alertStatusResponse?.alerts.count, 3)
    }

    func testAddReminderStatusResponse() {
        let bundle = NotificationBundle()
        // bits 0, 1 = LOW_BG_REMINDER, HIGH_BG_REMINDER
        let response = ReminderStatusResponse(intMap: bitmask(0, 1))
        bundle.add(response)

        XCTAssertEqual(bundle.getNotificationCount(), 2)
        XCTAssertNotNil(bundle.reminderStatusResponse)
    }

    func testAddAlarmStatusResponse() {
        let bundle = NotificationBundle()
        // bit 2 = OCCLUSION_ALARM
        let response = AlarmStatusResponse(intMap: bitmask(2))
        bundle.add(response)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertNotNil(bundle.alarmStatusResponse)
    }

    func testAddCGMAlertStatusResponse() {
        let bundle = NotificationBundle()
        // bit 1 = FIXED_LOW_CGM_ALERT
        let response = CGMAlertStatusResponse(intMap: bitmask(1))
        bundle.add(response)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertNotNil(bundle.cgmAlertStatusResponse)
    }

    // MARK: - Last Updated Time Tests

    func testLastUpdatedTimeTracking() {
        let bundle = NotificationBundle()

        XCTAssertNil(bundle.lastUpdatedTime(for: AlertStatusResponse.self))

        let response = AlertStatusResponse(intMap: bitmask(0))
        let beforeAdd = Date()
        bundle.add(response)
        let afterAdd = Date()

        let lastUpdated = bundle.lastUpdatedTime(for: AlertStatusResponse.self)
        XCTAssertNotNil(lastUpdated)
        XCTAssertGreaterThanOrEqual(lastUpdated!, beforeAdd)
        XCTAssertLessThanOrEqual(lastUpdated!, afterAdd)
    }

    // MARK: - Static Helper Tests

    func testIsNotificationResponse() {
        XCTAssertTrue(NotificationBundle.isNotificationResponse(AlertStatusResponse(intMap: 0)))
        XCTAssertTrue(NotificationBundle.isNotificationResponse(ReminderStatusResponse(intMap: 0)))
        XCTAssertTrue(NotificationBundle.isNotificationResponse(AlarmStatusResponse(intMap: 0)))
        XCTAssertTrue(NotificationBundle.isNotificationResponse(CGMAlertStatusResponse(intMap: 0)))
        XCTAssertTrue(NotificationBundle.isNotificationResponse(MalfunctionStatusResponse(codeA: 0, codeB: 0)))

        // Non-notification responses should return false
        XCTAssertFalse(NotificationBundle.isNotificationResponse(ApiVersionRequest()))
    }

    func testAllRequestsReturnsExpectedCount() {
        let requests = NotificationBundle.allRequests()
        XCTAssertEqual(requests.count, 7)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentAccessSafety() {
        let bundle = NotificationBundle()
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 100

        for i in 0 ..< 100 {
            DispatchQueue.global().async {
                // Alternate between adding and reading
                if i % 2 == 0 {
                    let response = AlertStatusResponse(intMap: UInt64(1 << (i % 64)))
                    bundle.add(response)
                } else {
                    _ = bundle.get()
                    _ = bundle.getNotificationCount()
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // After all operations, count should still match items
        XCTAssertEqual(bundle.getNotificationCount(), bundle.get().count)
    }
}
