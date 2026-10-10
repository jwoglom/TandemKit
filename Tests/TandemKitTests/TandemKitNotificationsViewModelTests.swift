import Foundation
@testable import TandemKit
import XCTest

/// Covers how the notifications view model schedules its reads of the pump.
///
/// A caller that refreshes because something just happened — the tubing fill button coming back up
/// (#248) — cannot be answered by a read that was already talking to the pump when it asked, since
/// that read may have been sent before the event. Periodic polling has no event to be newer than,
/// so it skips a tick rather than queueing an extra read on top of the one already running.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitNotificationsViewModelTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var viewModel: TandemKitNotificationsViewModel!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: 0))
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        viewModel = TandemKitNotificationsViewModel(manager)
    }

    override func tearDown() {
        viewModel = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    func testARefreshWaitingOnAnEventGetsAReadOfItsOwn() {
        viewModel.refreshNotifications()
        XCTAssertTrue(viewModel.isRefreshing, "The first read is still in flight until the main queue runs")
        XCTAssertEqual(notificationReads, 1)

        var completed = false
        viewModel.refreshNotifications { completed = true }
        XCTAssertEqual(notificationReads, 1, "Queued behind the read that is already talking to the pump")

        // The in-flight read finishes and starts the queued pass.
        drainMainQueue()
        XCTAssertEqual(notificationReads, 2)
        XCTAssertFalse(completed, "The caller waits for the read that started after it asked")

        // The queued pass finishes.
        drainMainQueue()
        XCTAssertTrue(completed)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testAPollLandingMidReadDoesNotQueueAnExtraRead() {
        viewModel.refreshNotifications()
        viewModel.refreshNotificationsIfIdle()
        drainMainQueue()

        XCTAssertEqual(notificationReads, 1, "A poll with no event behind it can wait for its next tick")
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testAPollWithNothingInFlightReads() {
        viewModel.refreshNotificationsIfIdle()
        drainMainQueue()

        XCTAssertEqual(notificationReads, 1)
    }

    func testTheReadIsPublishedAndTimestamped() {
        bluetooth.stub(
            AlertStatusRequest.self,
            with: AlertStatusResponse(intMap: UInt64(1) << UInt64(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue))
        )

        viewModel.refreshNotifications()
        drainMainQueue()

        XCTAssertEqual(viewModel.notifications.map(\.name), ["LOW_INSULIN_ALERT"])
        XCTAssertNotNil(viewModel.lastRefreshTime, "The screen shows when the pump was last read")
    }

    /// Without a pump manager there is nothing to read, but the caller still has to be released —
    /// the fill screen keeps its complete button disabled until the completion comes back.
    func testRefreshWithoutAPumpManagerStillCallsBack() {
        let orphaned = TandemKitNotificationsViewModel(nil)

        var completed = false
        orphaned.refreshNotifications { completed = true }

        XCTAssertTrue(completed)
        XCTAssertFalse(orphaned.isRefreshing)
    }

    func testADismissalRemovesTheItemEvenAfterARefreshReplacedIt() {
        bluetooth.stub(
            AlertStatusRequest.self,
            with: AlertStatusResponse(intMap: UInt64(1) << UInt64(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue))
        )
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 0))
        viewModel.refreshNotifications()
        drainMainQueue()
        let item = viewModel.notifications[0]

        viewModel.refreshNotifications()
        var dismissed: Bool?
        viewModel.dismissNotification(item) { dismissed = $0 }
        drainMainQueue()

        XCTAssertEqual(dismissed, true)
        XCTAssertTrue(viewModel.notifications.isEmpty)
    }

    func testARefusedDismissalKeepsTheItemAndSaysSo() {
        bluetooth.stub(
            AlertStatusRequest.self,
            with: AlertStatusResponse(intMap: UInt64(1) << UInt64(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue))
        )
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 1))
        viewModel.refreshNotifications()
        drainMainQueue()

        var dismissed: Bool?
        viewModel.dismissNotification(viewModel.notifications[0]) { dismissed = $0 }
        drainMainQueue()

        XCTAssertEqual(dismissed, false)
        XCTAssertEqual(viewModel.notifications.map(\.name), ["LOW_INSULIN_ALERT"])
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDismissingWithoutAPumpManagerStillCallsBack() {
        let orphaned = TandemKitNotificationsViewModel(nil)

        var dismissed: Bool?
        orphaned.dismissNotification(NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT")) { dismissed = $0 }

        XCTAssertEqual(dismissed, false)
    }

    // MARK: - Helpers

    /// Every notification read sends exactly one `AlertStatusRequest`, so counting them counts reads.
    private var notificationReads: Int {
        bluetooth.sent(AlertStatusRequest.self).count
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }
}
