import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

final class AlertIntegrationTests: FaketandemIntegrationTestCase {
    private func raiseOcclusionAlarm(_ driver: FaketandemHarness.Driver) throws -> Alert {
        try harness.pair(driver)
        driver.delegate.addAlertResponder(driver.manager)
        try harness.client.suspend(reason: "occlusion")
        XCTAssertEqual(try harness.client.snapshot().alerts.count, 1, "the pump raised the occlusion alarm")
        _ = try harness.sync(driver)
        return try XCTUnwrap(
            driver.delegate.issuedAlerts.first { $0.identifier.alertIdentifier.hasPrefix("alarm.occlusion") },
            "the occlusion alarm reached the host: \(driver.delegate.issuedAlerts.map(\.identifier))"
        )
    }

    /// As Loop and Trio route it: by the alert's managerIdentifier to the responder registered under
    /// the pump manager's pluginIdentifier.
    private func acknowledgeInTheHost(_ alert: Alert, _ driver: FaketandemHarness.Driver) throws -> Error? {
        let box = ResultBox<Error?>()
        guard driver.delegate.acknowledgeAlert(alert.identifier, completion: { box.set($0) }) else {
            XCTFail("the host found no responder for \(alert.identifier)")
            return nil
        }
        let error = try box.wait("acknowledgeAlert completion", timeout: 60)
        driver.drainDelegate()
        return error
    }

    /// #592
    func testAnAlarmAcknowledgedInTheHostIsDismissedOnThePump() throws {
        let driver = makeDriver()
        let alert = try raiseOcclusionAlarm(driver)

        XCTAssertNil(try acknowledgeInTheHost(alert, driver))

        XCTAssertTrue(try harness.requestsSeen().map(\.message).contains("DismissNotificationRequest"))
        XCTAssertEqual(try harness.client.snapshot().alerts.count, 0, "the pump dropped the alarm")
        XCTAssertEqual(driver.delegate.retractedAlerts, [alert.identifier], "the read after the dismissal found it gone")
        XCTAssertEqual(driver.manager.state.issuedAlertIdentifiers, [])
    }

    func testAnAlarmThePumpRefusesToDismissIsIssuedToTheHostAgain() throws {
        let driver = makeDriver()
        let alert = try raiseOcclusionAlarm(driver)
        XCTAssertNotNil(try harness.client.armFault(FaketandemFaultSpec(.errorResponse, message: "DismissNotificationRequest")))

        XCTAssertNotNil(try acknowledgeInTheHost(alert, driver), "the host is told the pump still raises it")

        XCTAssertEqual(try harness.client.snapshot().alerts.count, 1, "the pump still raises the alarm")
        XCTAssertEqual(driver.delegate.issuedAlerts.filter { $0.identifier == alert.identifier }.count, 2)
        XCTAssertEqual(driver.delegate.retractedAlerts, [])
    }
}
