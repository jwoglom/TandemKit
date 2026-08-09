@testable import TandemKit
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
        let expected = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let aamResponse: HighestAamResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, aamResponse.cargo)
        XCTAssertEqual(12, aamResponse.aamId)
        XCTAssertEqual(0x2071, aamResponse.faultId)
        bundle.add(aamResponse)

        // Malfunction should be counted since codes are not in IGNORABLE_CODES
        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that ignorable malfunctions are not counted
    func testIgnorableMalfunctionNotCounted() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: 3-0x2026 (ignorable)
        let expected = HighestAamResponse(aamId: 3, faultId: 0x2026, remaining: Data([2, 0xFF, 0xFF]))
        let aamResponse: HighestAamResponse = MessageTester.test(
            "001079100b030000002620000002ffff2ab0",
            16,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, aamResponse.cargo)
        XCTAssertEqual(3, aamResponse.aamId)
        XCTAssertEqual(0x2026, aamResponse.faultId)
        bundle.add(aamResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 0)
        XCTAssertEqual(bundle.get().count, 0)
    }

    /// Verifies that malfunction is suppressed when its ID matches an alarm
    func testMalfunctionSuppressedByMatchingAlarm() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: aamId 12, and alarm bit 12 is BATTERY_SHUTDOWN_ALARM (known)
        let alarmResponse = AlarmStatusResponse(intMap: bitmask(12))
        bundle.add(alarmResponse)

        let expected = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let aamResponse: HighestAamResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(aamResponse)

        // Malfunction should be suppressed because aamId (12) matches BATTERY_SHUTDOWN_ALARM
        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is suppressed when its ID matches a known alert
    func testMalfunctionSuppressedByMatchingKnownAlert() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: aamId 12, and alert bit 12 is a known alert
        bundle.add(AlertStatusResponse(intMap: bitmask(12)))
        let expected = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let aamResponse: HighestAamResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(aamResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is NOT suppressed by a default/unknown reminder ID
    func testMalfunctionNotSuppressedByDefaultReminder() {
        let bundle = NotificationBundle()

        // PumpX2 comment payload: aamId 23, and reminder bit 23 is DEFAULT_REMINDER_23
        bundle.add(ReminderStatusResponse(intMap: bitmask(23)))
        let expected = HighestAamResponse(aamId: 23, faultId: 0x20A7, remaining: Data([2, 0xFF, 0xFF]))
        let aamResponse = HighestAamResponse(cargo: Data(hexadecimalString: "17000000a720000002ffff")!)
        MessageTester.assertHexEquals(expected.cargo, aamResponse.cargo)
        XCTAssertEqual(23, aamResponse.aamId)
        XCTAssertEqual(0x20A7, aamResponse.faultId)
        bundle.add(aamResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 2)
        XCTAssertEqual(bundle.get().count, 2)
    }

    /// Verifies that malfunction is suppressed when its ID matches a known CGM alert
    func testMalfunctionSuppressedByMatchingKnownCGMAlert() {
        let bundle = NotificationBundle()

        // PumpX2 test payload: aamId 12, and CGM alert bit 12 is known
        bundle.add(CGMAlertStatusResponse(intMap: bitmask(12)))
        let expected = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF]))
        let aamResponse: HighestAamResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )
        bundle.add(aamResponse)

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// Verifies that malfunction is NOT suppressed by a default/unknown CGM alert ID
    func testMalfunctionNotSuppressedByDefaultCGMAlert() {
        let bundle = NotificationBundle()

        // PumpX2 comment payload: aamId 23, and CGM alert bit 23 is DEFAULT_CGM_ALERT_23
        bundle.add(CGMAlertStatusResponse(intMap: bitmask(23)))
        let expected = HighestAamResponse(aamId: 23, faultId: 0x20A7, remaining: Data([2, 0xFF, 0xFF]))
        let aamResponse = HighestAamResponse(cargo: Data(hexadecimalString: "17000000a720000002ffff")!)
        MessageTester.assertHexEquals(expected.cargo, aamResponse.cargo)
        XCTAssertEqual(23, aamResponse.aamId)
        XCTAssertEqual(0x20A7, aamResponse.faultId)
        bundle.add(aamResponse)

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

    // MARK: - matchesActiveMalfunction Gate Tests

    /// A malfunction confirmed by the active AAM-bits (malfunction type) is surfaced.
    func testMalfunctionConfirmedByActiveAamBits() {
        let bundle = NotificationBundle()

        bundle.add(HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF])))
        // Active malfunction bits with bit 12 set.
        bundle.add(ActiveAamBitsResponse(
            unacknowledgedBitmask: 0,
            activeBitmask: 1 << 12,
            aamType: .malfunction
        ))

        XCTAssertEqual(bundle.getNotificationCount(), 1)
        XCTAssertEqual(bundle.get().count, 1)
    }

    /// A `HighestAamResponse` that is NOT confirmed by the active malfunction bits must not
    /// surface a phantom malfunction (the bug fixed by restoring matchesActiveMalfunction).
    func testMalfunctionSuppressedWhenActiveAamBitsLacksBit() {
        let bundle = NotificationBundle()

        bundle.add(HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF])))
        // Active malfunction bits present, but bit 12 is NOT set.
        bundle.add(ActiveAamBitsResponse(
            unacknowledgedBitmask: 0,
            activeBitmask: 0,
            aamType: .malfunction
        ))

        XCTAssertEqual(bundle.getNotificationCount(), 0)
        XCTAssertEqual(bundle.get().count, 0)
    }

    /// When no active malfunction bits exist, the malfunction bitmask confirms/denies the AAM.
    func testMalfunctionSuppressedByMalfunctionBitmaskWithoutBit() {
        let bundle = NotificationBundle()

        bundle.add(HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF])))
        // Malfunction bitmask present, but bit 12 not set.
        bundle.add(MalfunctionBitmaskStatusResponse(bitmask: 0))

        XCTAssertEqual(bundle.getNotificationCount(), 0)
        XCTAssertEqual(bundle.get().count, 0)
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
        XCTAssertTrue(NotificationBundle.isNotificationResponse(HighestAamResponse(aamId: 0, faultId: 0)))

        // Non-notification responses should return false
        XCTAssertFalse(NotificationBundle.isNotificationResponse(ApiVersionRequest()))
    }

    func testAllRequestsReturnsExpectedCount() {
        let requests = NotificationBundle.allRequests()
        XCTAssertEqual(requests.count, 7)
    }

    func testAllRequestsFiltersByApiVersion() {
        // Mobi v3.5 supports the active-AAM-bits requests.
        let mobi = NotificationBundle.allRequests(apiVersion: KnownApiVersion.mobiApiV3_5.value)
        XCTAssertEqual(mobi.count, 7)
        XCTAssertTrue(mobi.contains { $0 is ActiveAamBitsRequest })

        // Legacy v2.1 pumps do not support ActiveAamBitsRequest, but still get the core surfaces.
        let legacy = NotificationBundle.allRequests(apiVersion: KnownApiVersion.apiV2_1.value)
        XCTAssertFalse(legacy.contains { $0 is ActiveAamBitsRequest })
        XCTAssertTrue(legacy.contains { $0 is HighestAamRequest })
        XCTAssertTrue(legacy.contains { $0 is MalfunctionStatusRequest })
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

    // MARK: - NotificationItem Display Title Tests

    /// `displayTitle` shows the human-readable description when present, and falls back to
    /// the prettified enum name for name-only notifications (CGM alerts / reminders, which
    /// pumpX2 also leaves name-only) or when no description exists.
    func testNotificationItemDisplayTitle() {
        // Alerts / alarms carry a distinct description -> shown verbatim.
        let withDescription = NotificationItem(
            type: .alert,
            id: 0,
            name: "LOW_INSULIN_ALERT",
            notificationDescription: "Low amount of insulin remaining in the cartridge."
        )
        XCTAssertEqual(withDescription.displayTitle, "Low amount of insulin remaining in the cartridge.")

        // Description equal to the raw name (CGM alerts / reminders) -> prettified name.
        let descriptionEqualsName = NotificationItem(
            type: .cgmAlert,
            id: 2,
            name: "HIGH_CGM_ALERT",
            notificationDescription: "HIGH_CGM_ALERT"
        )
        XCTAssertEqual(descriptionEqualsName.displayTitle, "High Cgm Alert")

        // No description -> prettified name.
        let noDescription = NotificationItem(type: .reminder, id: 2, name: "SITE_CHANGE_REMINDER")
        XCTAssertEqual(noDescription.displayTitle, "Site Change Reminder")

        // Empty description -> prettified name.
        let emptyDescription = NotificationItem(
            type: .alarm,
            id: 3,
            name: "OCCLUSION_ALARM",
            notificationDescription: ""
        )
        XCTAssertEqual(emptyDescription.displayTitle, "Occlusion Alarm")
    }
}
