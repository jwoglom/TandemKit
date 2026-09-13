import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Base for the dose-reporting conformance scenarios (`docs/conformance-test-plan.md`).
///
/// On top of `FaketandemIntegrationTestCase` it holds the paired clocks (`clock`), a driver whose
/// delegate journals every call with the driver clock's time, the two host oracles, and the pump
/// timeline. The command helpers block on the manager's completion (pumping the run loop) and
/// return what the host would have been handed. `relaunch()` models the app restarting: the
/// manager is rebuilt from its persisted `rawValue` with a fresh delegate, and the journals of every
/// delegate the test has had are replayed in order when the oracles are fed.
class ConformanceTestCase: FaketandemIntegrationTestCase {
    /// The driver's `ManualClock`, in lock-step with the emulator's manual clock.
    private(set) var manualClock: ManualClock!
    private(set) var clock: ConformanceClock!
    /// Every delegate this test attached, oldest first; `relaunch()` appends one.
    private(set) var delegates: [MockPumpManagerDelegate] = []
    /// History and request-log positions when the test began, so the timeline and the request log
    /// exclude what earlier tests left behind.
    private(set) var historyStartSequence = 0
    private(set) var logStartSequence = 0

    /// The current driver; nil before `startDriver()` and between `shutDownDriver()`/`relaunch()`.
    var current: FaketandemHarness.Driver? { driver }

    /// Default command timeouts. Commands wait on a real pump exchange, so these are wall-clock.
    var commandTimeout: TimeInterval = 60
    var syncTimeout: TimeInterval = 180

    override func setUpWithError() throws {
        try super.setUpWithError()
        manualClock = ManualClock(Date())
        clock = ConformanceClock(driver: manualClock, client: harness.client)
        try clock.start()
        let snapshot = try harness.client.snapshot()
        historyStartSequence = snapshot.history.lastSequence
        logStartSequence = snapshot.requestLog.lastSeq
    }

    override func tearDownWithError() throws {
        // Time must move for the teardown handshake's wall-clock waits to line up with the pump;
        // the next test's reset puts the clock back to real mode anyway.
        try? clock?.unfreeze()
        try super.tearDownWithError()
        delegates = []
        clock = nil
        manualClock = nil
    }

    // MARK: - Driver lifecycle

    /// One driver on the shared clock, its delegate journaling with that clock.
    @discardableResult
    func startDriver(state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:])) -> FaketandemHarness.Driver {
        let driver = makeDriver(state: state, clock: manualClock)
        driver.delegate.journalClock = manualClock
        delegates.append(driver.delegate)
        return driver
    }

    /// Start, pair (seeded long-term key by default) and run the first sync, the state every
    /// scenario begins from.
    @discardableResult
    func startPairedDriver(method: FaketandemHarness.PairingMethod = FaketandemHarness.defaultPairingMethod) throws -> FaketandemHarness.Driver {
        let driver = startDriver()
        try harness.pair(driver, method: method)
        _ = try sync()
        return driver
    }

    /// The app restarts: persist `rawValue`, drop the manager, build a new one from the persisted
    /// state with a new delegate. Returns the new driver. The old delegate's journal is kept in
    /// `delegates`, so `feedOracles()` still sees every batch the host ever received.
    @discardableResult
    func relaunch() throws -> FaketandemHarness.Driver {
        let running = try XCTUnwrap(driver, "relaunch needs a running driver")
        let persisted = running.manager.state.rawValue
        try shutDownDriver()
        return startDriver(state: TandemPumpManagerState(rawValue: persisted))
    }

    /// A pump-side link drop (the pump disconnects the central), waited on until the pump sees the
    /// link down. The driver's auto-reconnect is left alone.
    func disconnectFromPump(timeout: TimeInterval = 10) throws {
        try harness.control.disconnectPump()
        try IntegrationWait.until("emulator to drop the link", timeout: timeout) {
            try !harness.client.snapshot().connection.connected
        }
    }

    // MARK: - Commands (each returns what the host's completion received)

    func enactBolus(
        units: Double,
        activationType: BolusActivationType = .manualNoRecommendation,
        timeout: TimeInterval? = nil
    ) throws -> PumpManagerError? {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<PumpManagerError?>()
        manager.enactBolus(units: units, activationType: activationType) { box.set($0) }
        let result = try box.wait("enactBolus completion", timeout: timeout ?? commandTimeout)
        drainDelegate()
        return result
    }

    func cancelBolus(timeout: TimeInterval? = nil) throws -> PumpManagerResult<DoseEntry?> {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<PumpManagerResult<DoseEntry?>>()
        manager.cancelBolus { box.set($0) }
        let result = try box.wait("cancelBolus completion", timeout: timeout ?? commandTimeout)
        drainDelegate()
        return result
    }

    func enactTempBasal(unitsPerHour: Double, duration: TimeInterval, timeout: TimeInterval? = nil) throws -> PumpManagerError? {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<PumpManagerError?>()
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { box.set($0) }
        let result = try box.wait("enactTempBasal completion", timeout: timeout ?? commandTimeout)
        drainDelegate()
        return result
    }

    func suspendDelivery(timeout: TimeInterval? = nil) throws -> Error? {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<Error?>()
        manager.suspendDelivery { box.set($0) }
        let result = try box.wait("suspendDelivery completion", timeout: timeout ?? commandTimeout)
        drainDelegate()
        return result
    }

    func resumeDelivery(timeout: TimeInterval? = nil) throws -> Error? {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<Error?>()
        manager.resumeDelivery { box.set($0) }
        let result = try box.wait("resumeDelivery completion", timeout: timeout ?? commandTimeout)
        drainDelegate()
        return result
    }

    /// A full `syncPumpData`; returns the lastSync it handed the host.
    func sync(timeout: TimeInterval? = nil) throws -> Date? {
        let running = try XCTUnwrap(driver, "no driver")
        return try harness.sync(running, timeout: timeout ?? syncTimeout)
    }

    /// Drains the current delegate queue so the journal holds every callback issued so far.
    func drainDelegate() {
        driver?.drainDelegate()
    }

    // MARK: - Oracles and timeline

    /// Fresh oracles fed with every `hasNewPumpEvents` batch every delegate of this test has
    /// received, in order. Built anew on each call so a scenario can inspect the fold at several
    /// points without double-feeding.
    func feedOracles(
        loop: LoopDoseStoreOracle = LoopDoseStoreOracle(),
        trio: TrioDoseStoreOracle = TrioDoseStoreOracle()
    ) -> (loop: LoopDoseStoreOracle, trio: TrioDoseStoreOracle) {
        drainDelegate()
        for delegate in delegates {
            delegate.feed(loop)
            delegate.feed(trio)
        }
        return (loop, trio)
    }

    /// Every `hasNewPumpEvents` batch across all delegates, oldest first.
    var allPumpEventBatches: [MockPumpManagerDelegate.PumpEventBatch] {
        drainDelegate()
        return delegates.flatMap { $0.pumpEventJournal.compactMap(\.pumpEventBatch) }
    }

    /// The pump's record since this test began.
    func timeline() throws -> PumpTimeline {
        PumpTimeline.build(
            snapshot: try harness.client.snapshot(),
            log: try harness.requestLog(since: logStartSequence),
            afterSequence: historyStartSequence
        )
    }

    // MARK: - Pump-side waits

    /// Steps both clocks until the pump reports the bolus finished, in `step`-second increments, or
    /// fails after `maxSeconds` of pump time.
    @discardableResult
    func advanceUntilBolusFinishes(bolusId: Int, step: TimeInterval = 5, maxSeconds: TimeInterval = 600) throws -> FaketandemSnapshot.LastBolus {
        var elapsed: TimeInterval = 0
        while elapsed < maxSeconds {
            let snapshot = try harness.client.snapshot()
            if let last = snapshot.lastBolus, last.bolusId == bolusId, !snapshot.bolus.active || snapshot.bolus.bolusId != bolusId {
                return last
            }
            try clock.advanceBoth(seconds: step, ticks: max(1, Int(step)))
            elapsed += step
        }
        throw IntegrationWaitTimeout(what: "pump to finish bolus \(bolusId)", timeout: maxSeconds)
    }
}
