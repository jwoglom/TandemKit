import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

final class AlertIntegrationTests: FaketandemIntegrationTestCase {
    /// The acknowledgement goes the way Loop and Trio route it, by the alert's managerIdentifier to
    /// the responder registered under the pump manager's pluginIdentifier (#592).
    func testAnAlarmAcknowledgedInTheHostIsDismissedOnThePump() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        driver.delegate.addAlertResponder(driver.manager)
        try harness.client.suspend(reason: "occlusion")
        XCTAssertEqual(try harness.client.snapshot().alerts.count, 1, "the pump raised the occlusion alarm")

        _ = try harness.sync(driver)

        let alert = try XCTUnwrap(
            driver.delegate.issuedAlerts.first { $0.identifier.alertIdentifier.hasPrefix("alarm.occlusion") },
            "the occlusion alarm reached the host: \(driver.delegate.issuedAlerts.map(\.identifier))"
        )
        let box = ResultBox<Error?>()
        guard driver.delegate.acknowledgeAlert(alert.identifier, completion: { box.set($0) }) else {
            return XCTFail("the host found no responder for \(alert.identifier)")
        }
        let error = try box.wait("acknowledgeAlert completion", timeout: 60)
        driver.drainDelegate()

        XCTAssertNil(error)
        XCTAssertTrue(try harness.requestsSeen().map(\.message).contains("DismissNotificationRequest"))
        XCTAssertEqual(try harness.client.snapshot().alerts.count, 0, "the pump dropped the alarm")
        XCTAssertEqual(driver.delegate.retractedAlerts, [alert.identifier], "the read after the dismissal found it gone")
        XCTAssertEqual(driver.manager.state.issuedAlertIdentifiers, [])
    }
}
