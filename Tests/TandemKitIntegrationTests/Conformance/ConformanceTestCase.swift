import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
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
        try clearLeftoverDelivery()
        // Earlier scenarios ran their clocks ahead of real time; starting behind their records
        // would put them in this scenario's future, where a fresh driver reports them as new.
        // The latest-dated, not the last: clearing a leftover dose above stamps its record now.
        let history = try harness.client.snapshot().history
        let newestRecord = history.latestTime ?? history.entries.map(\.time).max() ?? .distantPast
        let start = max(Date(), newestRecord.addingTimeInterval(.minutes(1)))
        manualClock = ManualClock(start)
        clock = ConformanceClock(driver: manualClock, client: harness.client)
        try clock.start(at: start)
        let snapshot = try harness.client.snapshot()
        historyStartSequence = snapshot.history.lastSequence
        logStartSequence = snapshot.requestLog.lastSeq
    }

    override func tearDownWithError() throws {
        // On this scenario's clock: cleared after the reset, a running bolus would end hours
        // before it started, on the real clock.
        try? clearLeftoverDelivery()
        // Time must move for the teardown handshake's wall-clock waits to line up with the pump;
        // the next test's reset puts the clock back to real mode anyway.
        try? clock?.unfreeze()
        try super.tearDownWithError()
        delegates = []
        clock = nil
        manualClock = nil
    }

    /// The emulator's reset leaves delivery alone, so a scenario that failed mid-dose would hand
    /// its running bolus or temp rate to the next one — and, back on the real clock, that bolus
    /// would finish inside the next scenario's history window. Done before the history and log
    /// marks are taken, so what it writes stays out of this test's timeline.
    ///
    /// Raw `send` rather than the typed actions: the action endpoints answer `{"state": …}`, which
    /// `FaketandemClient.action` decodes as a bare snapshot and rejects.
    private func clearLeftoverDelivery() throws {
        let snapshot = try harness.client.snapshot()
        if snapshot.bolus.active {
            try clearing("POST", "/api/state/bolus/abort")
        }
        if snapshot.basal.tempActive {
            try clearing("POST", "/api/state/tempbasal/stop")
        }
        if snapshot.basal.suspended {
            try clearing("POST", "/api/state/resume")
        }
    }

    /// One clearing call, treating HTTP 409 as success. The emulator is back on its real clock by
    /// the time this runs, so a leftover bolus can finish, or a temp rate expire, in the moment
    /// between the snapshot that saw it and this request; the action endpoints answer 409 ("no
    /// bolus is in progress") for exactly that, which is the state this wants anyway.
    private func clearing(_ method: String, _ path: String) throws {
        do {
            try harness.client.send(method, path)
        } catch let FaketandemClientError.http(status, _, _) where status == 409 {
            return
        }
    }

    /// Empties the pump's log; this scenario's records then start at sequence 1.
    func eraseHistory() throws {
        try harness.client.eraseHistory()
        historyStartSequence = 0
    }

    // MARK: - Driver lifecycle

    /// One driver on the shared clock; the harness gives its delegate that clock to journal with.
    @discardableResult
    func startDriver(state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:])) -> FaketandemHarness.Driver {
        let driver = makeDriver(state: state, clock: manualClock)
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

    /// Leaves the driver no pump history to recover a bolus volume from, for scenarios where the
    /// volume must be unknown everywhere (#448). Persists across `relaunch()`.
    func turnOffHistoryBackfill(_ driver: FaketandemHarness.Driver) {
        driver.manager.state.featureFlags[.historyBackfill] = false
    }

    /// Drops every `LastBolusStatus` answer, whichever version the driver asks for.
    func dropEveryLastBolusStatus() throws {
        for name in ["LastBolusStatusV3Request", "LastBolusStatusV2Request", "LastBolusStatusRequest"] {
            var fault = FaketandemFaultSpec(.dropResponse, message: name)
            fault.every = true
            XCTAssertNotNil(try harness.client.armFault(fault))
        }
    }

    /// Syncs a minute apart until `raw`'s finalized report arrives: a backfill tick reads history
    /// after the sync's bolus reconciliation, so a record it finds is used by the next sync.
    func syncUntilFinalized(raw: Data, maxSyncs: Int = 4) throws -> NewPumpEvent {
        for _ in 0 ..< maxSyncs {
            _ = try sync()
            drainDelegate()
            if let finalized = allPumpEventBatches.flatMap(\.events).first(where: { $0.raw == raw && $0.dose?.isMutable == false }) {
                return finalized
            }
            try clock.advanceBoth(seconds: .minutes(1))
        }
        throw IntegrationWaitTimeout(what: "finalized report of \(LoopDoseStoreOracle.describe(raw))", timeout: TimeInterval(maxSyncs) * 60)
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

    func syncPumpTime(timeout: TimeInterval? = nil) throws -> Result<Void, PumpManagerError> {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let box = ResultBox<Result<Void, PumpManagerError>>()
        manager.syncPumpTime { box.set($0) }
        let result = try box.wait("syncPumpTime completion", timeout: timeout ?? syncTimeout)
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
        batchesFedToOracles = delegates.reduce(0) { $0 + $1.feed(loop, trio) }
        return (loop, trio)
    }

    /// How many batches the last `feedOracles()` fed. `allPumpEventBatches.count` read later can be
    /// higher: the driver's own reconnects, syncs and qualifying-event reads keep reporting.
    private(set) var batchesFedToOracles = 0

    /// Every `hasNewPumpEvents` batch across all delegates, oldest first.
    var allPumpEventBatches: [MockPumpManagerDelegate.PumpEventBatch] {
        drainDelegate()
        return delegates.flatMap { $0.pumpEventJournal.compactMap(\.pumpEventBatch) }
    }

    /// Replays every batch the host has received, in order, and reports each dose that was live and
    /// mutable at the host when a `replacePendingEvents: true` batch arrived without carrying it —
    /// the doses LoopKit's report-or-delete rule (guide §3, §5) deletes.
    func completeBatchOmissions() -> [String] {
        drainDelegate()
        let oracle = LoopDoseStoreOracle()
        var omissions: [String] = []
        for delegate in delegates {
            for entry in delegate.journal {
                guard let batch = entry.pumpEventBatch else { continue }
                if batch.replacePendingEvents {
                    let carried = Set(batch.events.map(\.raw))
                    for dose in oracle.doses where dose.isMutable && !carried.contains(dose.raw ?? Data()) {
                        let batchEvents = batch.events.map { LoopDoseStoreOracle.describe($0.raw) }
                        omissions.append("  \(LoopDoseStoreOracle.describe(dose)) dropped by a replacing batch of \(batchEvents)")
                    }
                }
                oracle.addPumpEvents(
                    batch.events,
                    lastReconciliation: batch.lastReconciliation,
                    replacePendingEvents: batch.replacePendingEvents,
                    now: entry.hostNow
                )
            }
        }
        return omissions
    }

    /// The pump's record since this test began, built from the full history feed
    /// (`GET /api/history`) rather than the 50-record tail in the snapshot, which a scenario
    /// running for a while silently outgrows.
    func timeline() throws -> PumpTimeline {
        PumpTimeline.build(
            snapshot: try harness.client.snapshot(),
            history: try harness.client.history(since: historyStartSequence),
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
