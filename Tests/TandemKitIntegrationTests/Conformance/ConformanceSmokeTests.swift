import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Exercises the whole conformance rig once: paired clocks, journaling delegate, both oracles and
/// the pump timeline, on the plainest scenario there is — one bolus, reported while running and
/// after it finished. Every scenario in the plan is this shape with something going wrong in the
/// middle.
final class ConformanceSmokeTests: ConformanceTestCase {
    private static let units = 1.0
    /// The pump delivers at the rate the driver's estimate assumes
    /// (`TandemPumpCapabilities.estimatedBolusDuration`), so the driver's finalized `endDate` and
    /// the pump's completion coincide: this test checks the rig, not end-date fidelity. Whether the
    /// driver takes the end from the pump's record rather than its own estimate is a scenario
    /// (plan A1, E), and it does not — at any other rate the timeline diff reports the end mismatch.
    private static let deliveryRate = units / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: units)

    func testBolusReportedWhileRunningAndFinalizedIsOneDoseInBothHosts() throws {
        let driver = try startPairedDriver()
        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate])
        let batchesBeforeEnact = allPumpEventBatches.count

        // Enact: the mutable dose must be registered up front (guide §10).
        XCTAssertNil(try enactBolus(units: Self.units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let enactBatches = Array(allPumpEventBatches.dropFirst(batchesBeforeEnact))
        let started = try XCTUnwrap(enactBatches.flatMap(\.events).first { $0.dose?.type == .bolus }, "enact must report the bolus")
        XCTAssertEqual(started.dose?.isMutable, true)
        let raw = started.raw

        // Sync while the pump is still delivering: same raw, still mutable.
        try clock.advanceBoth(seconds: 2, ticks: 2)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the pump should still be delivering")
        _ = try sync()
        let midRun = feedOracles()
        let running = try XCTUnwrap(midRun.loop.assertSingleDose(raw: raw, "after a sync mid-delivery"))
        XCTAssertTrue(running.isMutable, "a running bolus stays mutable: \(LoopDoseStoreOracle.describe(running))")
        XCTAssertEqual(midRun.trio.boluses.count, 1)

        // Let the pump finish, move the driver past its estimate + reconcile grace, sync again.
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.units)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.units) + .minutes(2))
        _ = try sync()

        let finalized = try IntegrationWait.value("finalized bolus report", timeout: 30) {
            self.allPumpEventBatches.flatMap(\.events).first { $0.raw == raw && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.deliveredUnits, Self.units)

        // Host side: one permanent dose in Loop, one bolus row in Trio at the final amount.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, Self.units)
        XCTAssertEqual(loop.callCount, allPumpEventBatches.count, "every batch reaches the oracle")
        XCTAssertNotNil(loop.lastReconciliation)
        XCTAssertEqual(loop.lastReconciliation, driver.manager.state.lastReconciliation)
        XCTAssertGreaterThan(loop.iob(at: clock.now), 0)
        XCTAssertEqual(loop.iob(at: clock.now.addingTimeInterval(.hours(6))), 0, accuracy: 0.0001)

        trio.assertNoDuplicates()
        trio.assertSingleBolus(at: started.date, amount: Self.units)
        XCTAssertTrue(trio.skipped.filter { $0.reason != .duplicate(.bolus) }.isEmpty, "Trio dropped: \(trio.skipped)")

        // Pump side: the timeline knows the bolus, and agrees with what Loop stored.
        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "timeline: \(timeline)")
        XCTAssertEqual(pumpBolus.programmedUnits, Self.units)
        XCTAssertEqual(pumpBolus.deliveredUnits, Self.units)
        XCTAssertTrue(pumpBolus.isFinished)
        XCTAssertEqual(pumpBolus.sourceId, 8, "an app-commanded bolus is BLUETOOTH_REMOTE_BOLUS")
        timeline.assertMatches(loop)

        // The journal itself: ordered, clock-stamped, and holding more than dose batches.
        let journal = driver.delegate.journal
        XCTAssertEqual(journal.map(\.index), Array(0 ..< journal.count))
        XCTAssertTrue(journal.allSatisfy { $0.clockTime != nil }, "every entry carries the driver clock")
        XCTAssertTrue(journal.contains { if case .statusUpdate = $0.kind { return true } else { return false } })
        XCTAssertTrue(journal.contains { if case .reservoirReading = $0.kind { return true } else { return false } })
    }

    func testRelaunchKeepsTheJournalAcrossDelegates() throws {
        try startPairedDriver()
        let before = allPumpEventBatches.count
        XCTAssertGreaterThan(before, 0, "the first sync reports a boundary")

        let relaunched = try relaunch()
        XCTAssertEqual(delegates.count, 2)
        try clock.advanceBoth(seconds: .minutes(5))
        _ = try sync()

        XCTAssertGreaterThan(allPumpEventBatches.count, before, "the relaunched driver's batches are journaled too")
        let (loop, _) = feedOracles()
        XCTAssertEqual(loop.callCount, allPumpEventBatches.count)
        XCTAssertEqual(loop.lastReconciliation, relaunched.manager.state.lastReconciliation)
        XCTAssertTrue(loop.doses.isEmpty, "no dose was ever delivered: \(loop.doses)")
        try timeline().assertMatches(loop)
    }
}
