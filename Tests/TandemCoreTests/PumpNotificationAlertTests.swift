@testable import TandemCore
import XCTest

final class PumpNotificationAlertTests: XCTestCase {
    // MARK: - Stable identifier

    func testStableIdentifierIsStableAcrossInstances() {
        let first = NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM")
        let second = NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM")

        // `id` is a per-fetch UUID and differs; the stable identifier must not.
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.stableIdentifier, second.stableIdentifier)
        XCTAssertEqual(first.stableIdentifier, "alarm.2")
    }

    func testStableIdentifierDistinguishesCategoriesAndIds() {
        // The several CARTRIDGE_ALARM bit positions share an enum name but must map to
        // distinct identifiers, as must the same bit across categories.
        let identifiers = [
            NotificationItem(type: .alarm, id: 0, name: "CARTRIDGE_ALARM"),
            NotificationItem(type: .alarm, id: 1, name: "CARTRIDGE_ALARM"),
            NotificationItem(type: .alarm, id: 5, name: "CARTRIDGE_ALARM"),
            NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT"),
            NotificationItem(type: .cgmAlert, id: 0, name: "DEFAULT_CGM_ALERT_0"),
            NotificationItem(type: .malfunction, id: 12, name: "12-0x2071")
        ].map(\.stableIdentifier)

        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }

    func testParseStableIdentifierRoundTrip() {
        for type in NotificationItem.NotificationType.allCases {
            let item = NotificationItem(type: type, id: 4462, name: "NAME")
            let parsed = NotificationItem.parseStableIdentifier(item.stableIdentifier)
            XCTAssertEqual(parsed?.type, type)
            XCTAssertEqual(parsed?.notificationId, 4462)
        }
    }

    func testParseStableIdentifierRejectsForeignIdentifiers() {
        XCTAssertNil(NotificationItem.parseStableIdentifier(""))
        XCTAssertNil(NotificationItem.parseStableIdentifier("alarm"))
        XCTAssertNil(NotificationItem.parseStableIdentifier("alarm."))
        XCTAssertNil(NotificationItem.parseStableIdentifier(".2"))
        XCTAssertNil(NotificationItem.parseStableIdentifier("alarm.-1"))
        XCTAssertNil(NotificationItem.parseStableIdentifier("alarm.two"))
        XCTAssertNil(NotificationItem.parseStableIdentifier("occlusion.2"))
    }

    // MARK: - Severity

    func testSeverityMapping() {
        XCTAssertEqual(NotificationItem.NotificationType.alarm.severity, .critical)
        XCTAssertEqual(NotificationItem.NotificationType.malfunction.severity, .critical)
        XCTAssertEqual(NotificationItem.NotificationType.alert.severity, .timeSensitive)
        XCTAssertEqual(NotificationItem.NotificationType.cgmAlert.severity, .timeSensitive)
        XCTAssertEqual(NotificationItem.NotificationType.reminder.severity, .informational)
    }

    // MARK: - Alert content

    func testAlertTitle() {
        XCTAssertEqual(NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM").alertTitle, "Pump Alarm")
        XCTAssertEqual(NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT").alertTitle, "Pump Alert")
        XCTAssertEqual(NotificationItem(type: .malfunction, id: 12, name: "12-0x2071").alertTitle, "Pump Malfunction")
        XCTAssertEqual(NotificationItem(type: .cgmAlert, id: 2, name: "HIGH_CGM_ALERT").alertTitle, "CGM Alert")
    }

    func testAlertBodyPrefersPumpDescription() {
        let item = NotificationItem(
            type: .alert,
            id: 0,
            name: "LOW_INSULIN_ALERT",
            notificationDescription: "Low amount of insulin remaining in the cartridge."
        )
        XCTAssertEqual(item.alertBody, "Low amount of insulin remaining in the cartridge.")
    }

    func testMalfunctionAlertBodyIncludesFaultCode() {
        let item = NotificationItem(
            type: .malfunction,
            id: 12,
            name: "12-0x2071",
            notificationDescription: "Pump malfunction detected."
        )
        XCTAssertEqual(item.alertBody, "Pump malfunction detected. (12-0x2071)")
    }

    func testAcknowledgeActionLabel() {
        XCTAssertEqual(NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT").acknowledgeActionLabel, "Dismiss")
        XCTAssertEqual(NotificationItem(type: .malfunction, id: 12, name: "12-0x2071").acknowledgeActionLabel, "OK")
    }

    // MARK: - Fetched categories

    func testFetchedCategoriesEmptyForFreshBundle() {
        XCTAssertTrue(NotificationBundle().fetchedCategories.isEmpty)
    }

    func testFetchedCategoriesTracksArrivedResponses() {
        let bundle = NotificationBundle()

        bundle.add(AlertStatusResponse(intMap: 0))
        XCTAssertEqual(bundle.fetchedCategories, [.alert])

        bundle.add(AlarmStatusResponse(intMap: 0))
        XCTAssertEqual(bundle.fetchedCategories, [.alert, .alarm])

        bundle.add(ReminderStatusResponse(intMap: 0))
        bundle.add(CGMAlertStatusResponse(intMap: 0))
        bundle.add(HighestAamResponse(aamId: 0, faultId: 0))
        XCTAssertEqual(bundle.fetchedCategories, Set(NotificationItem.NotificationType.allCases))
    }

    func testFetchedCategoryWithEmptyBitmaskStillCountsAsFetched() {
        // An empty alarm bitmask is a real "no alarms" answer, distinct from "the request
        // failed" — it must allow retraction of previously-issued alarms.
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: 0))

        XCTAssertTrue(bundle.fetchedCategories.contains(.alarm))
        XCTAssertTrue(bundle.get().isEmpty)
    }
}
