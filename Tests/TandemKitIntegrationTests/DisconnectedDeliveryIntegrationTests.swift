import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The pump disconnected detail (`LastKnownBasalDelivery`) from the state a real sync and the app's
/// own commands leave once the pump goes out of range.
final class DisconnectedDeliveryIntegrationTests: FaketandemIntegrationTestCase {
    private static let profileRate = 1.0

    override func tearDownWithError() throws {
        if let harness {
            try harness.client.armFault(FaketandemFaultSpec(.radioOn))
            let snapshot = try harness.client.snapshot()
            if snapshot.basal.tempActive {
                try harness.client.stopTempBasal()
            }
            if snapshot.basal.suspended {
                try harness.client.resume(clearAlarms: true)
            }
        }
        try super.tearDownWithError()
    }

    private func stageDriver() throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": Self.profileRate])
        let driver = makeDriver()
        driver.manager.state.insulinType = .novolog
        driver.manager.state.basalRateSchedule = BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]
        )!
        try harness.pair(driver)
        XCTAssertNotNil(try harness.sync(driver))
        return driver
    }

    private func goOutOfRange(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
        XCTAssertEqual(driver.manager.connectionIssue, .pumpUnreachable)
    }

    private func describe(_ driver: FaketandemHarness.Driver) throws -> String {
        try XCTUnwrap(driver.manager.lastKnownBasalDelivery).localizedDescription(appName: "Trio", now: driver.clock.now)
    }

    func testATempBasalRunningAtTheDropIsDescribedUntilItsEndAndAfter() throws {
        let driver = try stageDriver()
        let clock = try XCTUnwrap(driver.clock as? ManualClock)
        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactTempBasal(unitsPerHour: 0.5, for: .minutes(30)) { box.set($0) }
        XCTAssertNil(try box.wait("enactTempBasal completion", timeout: 60))
        driver.drainDelegate()
        let end = driver.manager.state.basalDose.estimatedEndDate

        try goOutOfRange(driver)

        let lastContact = try XCTUnwrap(driver.manager.state.lastReconciliation)
        XCTAssertEqual(
            driver.manager.lastKnownBasalDelivery,
            LastKnownBasalDelivery(
                lastContact: lastContact,
                delivery: .tempBasal(unitsPerHour: 0.5, endDate: end, profileUnitsPerHourAfter: Self.profileRate)
            )
        )

        clock.set(lastContact.addingTimeInterval(.minutes(5)))
        let running = try describe(driver)
        XCTAssertTrue(
            running.hasPrefix("Trio last connected to your pump 5 minutes ago. At that time, the pump was delivering basal at a temp rate of 0.50 U/hr, and will return to the profile basal rate of 1.00 U/hr at "),
            running
        )

        clock.set(end)
        let ended = try describe(driver)
        XCTAssertTrue(ended.contains("delivering basal at 0.50 U/hr with a planned end time of"), ended)
        XCTAssertTrue(ended.hasSuffix("We expect the pump to have returned to its profile basal rate of 1.00 U/hr and it will continue as programmed until reconnected."), ended)
    }

    func testThePumpOnItsProfileAtTheDropIsDescribedAtItsProfileRate() throws {
        let driver = try stageDriver()
        try goOutOfRange(driver)

        XCTAssertEqual(driver.manager.lastKnownBasalDelivery?.delivery, .profile(unitsPerHour: Self.profileRate))
        let lastContact = try XCTUnwrap(driver.manager.state.lastReconciliation)
        try XCTUnwrap(driver.clock as? ManualClock).set(lastContact.addingTimeInterval(.minutes(12)))
        XCTAssertEqual(
            try describe(driver),
            "Trio last connected to your pump 12 minutes ago. At that time, the pump was delivering basal at the profile basal rate of 1.00 U/hr and will continue to deliver basal as programmed until reconnected."
        )
    }

    func testAPumpTheAppSuspendedBeforeTheDropIsDescribedAsSuspended() throws {
        let driver = try stageDriver()
        let box = ResultBox<Error?>()
        driver.manager.suspendDelivery { box.set($0) }
        XCTAssertNil(try box.wait("suspendDelivery completion", timeout: 60))
        driver.drainDelegate()

        try goOutOfRange(driver)

        XCTAssertEqual(driver.manager.lastKnownBasalDelivery?.delivery, .suspended)
        XCTAssertTrue(try describe(driver).contains("At that time, insulin delivery was suspended."))
    }
}
