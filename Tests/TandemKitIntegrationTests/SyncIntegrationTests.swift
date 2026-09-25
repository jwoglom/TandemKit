import LoopKit
@testable import TandemKit
import XCTest

final class SyncIntegrationTests: FaketandemIntegrationTestCase {
    func testSyncPumpDataReportsStatusReservoirAndTheReconciliationBoundary() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        try harness.client.setState(["reservoir_units": 137.0, "battery_percent": 64])
        let statusUpdatesBefore = driver.delegate.statusUpdates.count
        let batchesBefore = driver.delegate.pumpEventBatches.count

        let lastSync = try harness.sync(driver)

        let boundary = try XCTUnwrap(driver.manager.state.lastReconciliation, "an answered sync stamps the boundary")
        XCTAssertEqual(lastSync, boundary)
        XCTAssertGreaterThan(driver.bluetooth.responseCount, 0)
        XCTAssertGreaterThan(driver.delegate.statusUpdates.count, statusUpdatesBefore, "the host must see a status update")

        XCTAssertEqual(driver.delegate.reservoirReadings.count, 1, "one reservoir report per sync")
        XCTAssertFalse(driver.manager.state.lastReservoirReadingNeedsReport)
        XCTAssertEqual(driver.delegate.reservoirReadings.last?.units, 137, "the reservoir the pump reports")
        XCTAssertEqual(driver.manager.reservoirLevel?.unitVolume, 137)
        XCTAssertEqual(driver.manager.state.lastBatteryReading?.chargeRemaining, 0.64)

        let batches = Array(driver.delegate.pumpEventBatches.dropFirst(batchesBefore))
        XCTAssertFalse(batches.isEmpty, "the sync must have reported something")
        let boundaryBatch = batches.last { $0.events.isEmpty }
        XCTAssertEqual(boundaryBatch?.lastReconciliation, boundary, "a quiet sync still carries its boundary")
        XCTAssertEqual(
            boundaryBatch?.replacePendingEvents,
            false,
            "a boundary-only report must not purge the host's pending mutable doses"
        )
        XCTAssertTrue(
            driver.delegate.errors.isEmpty,
            "no communication errors on a healthy pump: \(driver.delegate.errors)"
        )

        let messages = try harness.requestsSeen().map(\.message)
        for expected in ["InsulinStatusRequest", "CurrentBolusStatusRequest", "CurrentBasalStatusRequest"] {
            XCTAssertTrue(messages.contains(expected), "sync must read \(expected); pump saw \(messages)")
        }
    }

    func testSecondSyncIsQuietAndAdvancesTheBoundary() throws {
        let clock = ManualClock(Date())
        let driver = makeDriver(clock: clock)
        try harness.pair(driver)
        let first = try XCTUnwrap(try harness.sync(driver))

        clock.advance(by: .minutes(5))
        let batchesBefore = driver.delegate.pumpEventBatches.count
        let second = try XCTUnwrap(try harness.sync(driver))

        XCTAssertEqual(second, first.addingTimeInterval(.minutes(5)))
        XCTAssertEqual(driver.manager.state.lastReconciliation, second)
        let batches = Array(driver.delegate.pumpEventBatches.dropFirst(batchesBefore))
        XCTAssertFalse(batches.isEmpty)
        for batch in batches {
            XCTAssertTrue(batch.events.isEmpty, "a steady-state sync has no dose to report: \(batch.events)")
            XCTAssertFalse(batch.replacePendingEvents)
        }
        XCTAssertEqual(batches.last?.lastReconciliation, second)
    }
}
