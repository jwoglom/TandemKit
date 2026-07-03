import LoopKit
import TandemCore
@testable import TandemKit
import XCTest

final class TandemAlertReconcilerTests: XCTestCase {
    private let allSurfaced: Set<NotificationItem.NotificationType> = [.alert, .alarm, .malfunction]
    private let allFetched: Set<NotificationItem.NotificationType> = [
        .alert, .alarm, .reminder, .cgmAlert, .malfunction
    ]

    private func occlusionAlarm() -> NotificationItem {
        NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM")
    }

    func testNewNotificationIsIssued() {
        let result = TandemAlertReconciler.reconcile(
            activeItems: [occlusionAlarm()],
            fetchedCategories: allFetched,
            issuedIdentifiers: [],
            surfacedCategories: allSurfaced
        )

        XCTAssertEqual(result.itemsToIssue.map(\.stableIdentifier), ["alarm.2"])
        XCTAssertTrue(result.identifiersToRetract.isEmpty)
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alarm.2"])
    }

    func testUnchangedNotificationsProduceNoDelegateCalls() {
        let result = TandemAlertReconciler.reconcile(
            activeItems: [occlusionAlarm()],
            fetchedCategories: allFetched,
            issuedIdentifiers: ["alarm.2"],
            surfacedCategories: allSurfaced
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alarm.2"])
    }

    func testClearedNotificationIsRetractedWhenCategoryWasFetched() {
        let result = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: allFetched,
            issuedIdentifiers: ["alarm.2"],
            surfacedCategories: allSurfaced
        )

        XCTAssertTrue(result.itemsToIssue.isEmpty)
        XCTAssertEqual(result.identifiersToRetract, ["alarm.2"])
        XCTAssertTrue(result.updatedIssuedIdentifiers.isEmpty)
    }

    func testMissingCategoryFetchDoesNotRetract() {
        // The alarm status request failed this pass — absence is not evidence of clearing.
        let result = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: [.alert, .cgmAlert],
            issuedIdentifiers: ["alarm.2"],
            surfacedCategories: allSurfaced
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alarm.2"])
    }

    func testNoLongerSurfacedCategoryIsRetractedEvenWithoutFetch() {
        // CGM forwarding was switched off: retract its alerts even though nothing was
        // fetched (configureForwardCGMAlerts reconciles immediately).
        let result = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: [],
            issuedIdentifiers: ["cgmAlert.2", "alarm.2"],
            surfacedCategories: allSurfaced
        )

        XCTAssertEqual(result.identifiersToRetract, ["cgmAlert.2"])
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alarm.2"])
    }

    func testUnparseableIdentifierIsRetracted() {
        let result = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: [],
            issuedIdentifiers: ["legacy-opaque-identifier"],
            surfacedCategories: allSurfaced
        )

        XCTAssertEqual(result.identifiersToRetract, ["legacy-opaque-identifier"])
        XCTAssertTrue(result.updatedIssuedIdentifiers.isEmpty)
    }

    func testMixedIssueAndRetractInOnePass() {
        let lowInsulin = NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT")

        let result = TandemAlertReconciler.reconcile(
            activeItems: [lowInsulin],
            fetchedCategories: allFetched,
            issuedIdentifiers: ["alarm.2"],
            surfacedCategories: allSurfaced
        )

        XCTAssertEqual(result.itemsToIssue.map(\.stableIdentifier), ["alert.0"])
        XCTAssertEqual(result.identifiersToRetract, ["alarm.2"])
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alert.0"])
    }

    func testDuplicateStableIdentifiersIssueOnce() {
        let result = TandemAlertReconciler.reconcile(
            activeItems: [occlusionAlarm(), occlusionAlarm()],
            fetchedCategories: allFetched,
            issuedIdentifiers: [],
            surfacedCategories: allSurfaced
        )

        XCTAssertEqual(result.itemsToIssue.count, 1)
        XCTAssertEqual(result.updatedIssuedIdentifiers, ["alarm.2"])
    }

    func testMalfunctionRetractedOnlyAfterHighestAamFetch() {
        let notFetched = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: [.alert, .alarm],
            issuedIdentifiers: ["malfunction.12"],
            surfacedCategories: allSurfaced
        )
        XCTAssertTrue(notFetched.isEmpty)

        let fetched = TandemAlertReconciler.reconcile(
            activeItems: [],
            fetchedCategories: [.malfunction],
            issuedIdentifiers: ["malfunction.12"],
            surfacedCategories: allSurfaced
        )
        XCTAssertEqual(fetched.identifiersToRetract, ["malfunction.12"])
    }

    // MARK: - State persistence

    func testIssuedAlertIdentifiersRoundTripThroughRawValue() {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.issuedAlertIdentifiers = ["alarm.2", "malfunction.12"]
        state.forwardCGMAlerts = true

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.issuedAlertIdentifiers, ["alarm.2", "malfunction.12"])
        XCTAssertTrue(restored.forwardCGMAlerts)
    }

    func testIssuedAlertIdentifiersDefaultEmptyOnLegacyRawValue() {
        // Raw state persisted by a driver version that predates alert surfacing.
        let restored = TandemPumpManagerState(rawValue: [:])

        XCTAssertTrue(restored.issuedAlertIdentifiers.isEmpty)
        XCTAssertFalse(restored.forwardCGMAlerts)
    }
}
