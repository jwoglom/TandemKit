import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group K (`docs/conformance-test-plan.md`): a pump manager's first connection to a pump,
/// whatever the pump did before, through setup as `TandemKitScanViewModel` and the Load Pump History
/// step run it: pairing, the onboarding writes and a sync with no host attached, the load or not, and
/// then the host adopting the manager (AGENTS.md "Setup history load"). The pump's past is staged on
/// faketandem's own clock before this app's driver exists: on the pump's screen, and by another app
/// over Bluetooth, which then goes away. Staged changes fall mid-cycle, as a pump's do: the cycle
/// runs every 5 minutes from the start, and a resume on one restarts it.
final class SetupHistoryLoadConformanceTests: ConformanceTestCase {
    private static let profileRate = FaketandemHarness.defaultBasalRate
    private static let bolusRate = 0.05
    private static let cycle: TimeInterval = 300

    /// The delegates before this index are the other app's, whose host is not this one.
    private var hostDelegatesFrom = 0
    private var otherAppState: [String: Any]?
    private var stagingStart = Date.distantPast

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        try harness.client.setState(["bolus_rate_units_per_second": Self.bolusRate])
        stagingStart = clock.now
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try harness.client.setState(["basal_cycle_enabled": false])
            } catch {
                XCTFail("restoring the pump failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    // MARK: - The pump's past

    /// Starts both clocks `minute` minutes before now, so this app pairs at the phone's real time,
    /// which the driver also reads, as a new state's basal dose does.
    private func pairing(at minute: Double) throws {
        stagingStart = try clock.start(at: Date().addingTimeInterval(-.minutes(minute)))
    }

    /// Minutes from the start of staging, on the clocks both sides share.
    private func at(_ minutes: Double) throws {
        try advance(to: stagingStart.addingTimeInterval(.minutes(minutes)))
    }

    private func minutes(_ minutes: Double) -> Date {
        stagingStart.addingTimeInterval(.minutes(minutes))
    }

    /// One minute a tick, so the pump's cycle and boluses run as they would.
    private func advance(to date: Date) throws {
        let seconds = date.timeIntervalSince(clock.now)
        guard seconds > 0 else { return }
        try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds / 60)))
    }

    private func runBasalCycle() throws {
        try harness.client.setState(["basal_cycle_enabled": true])
    }

    private struct PumpInUse {
        /// The other app's temps, the last still running when this app pairs.
        let otherAppTempRateIds: [Int]
        let pumpScreenTempRateId: Int
    }

    /// Six and a half hours of a pump in use, a BasalDelivery record every 5 minutes: on its screen
    /// boluses, one stopped part-way, a 150% temp and a suspend and resume, and older than the load's
    /// window a bolus and another suspend; another app's bolus over Bluetooth, its 200% temp that runs
    /// out and its 60% temp with 40 minutes left when this app pairs, at 392.
    private func stagePumpInUse() throws -> PumpInUse {
        try pairing(at: 392)
        try runBasalCycle()
        try at(7)
        try bolusOnThePump(units: 1.0)
        try at(17)
        try harness.client.suspend(reason: "user")
        try at(25)
        try harness.client.resume()
        try at(62)
        try bolusOnThePump(units: 2.5)

        try at(122)
        var otherAppTempRateIds: [Int] = []
        try anotherApp { driver in
            XCTAssertNil(try self.enactBolus(units: 3.0))
            try self.advanceUntilBolusFinishes(bolusId: try XCTUnwrap(driver.manager.state.bolusDose?.bolusId))
            try self.at(142)
            XCTAssertNil(try self.enactTempBasal(unitsPerHour: 2 * Self.profileRate, duration: .minutes(30)))
            otherAppTempRateIds.append(try XCTUnwrap(try self.harness.client.snapshot().basal.tempRateId))
        }

        try at(182)
        try harness.client.startTempBasal(percent: 150, durationMinutes: 30)
        let pumpScreenTempRateId = try XCTUnwrap(try harness.client.snapshot().basal.tempRateId)
        try at(242)
        try bolusOnThePump(units: 2.0, stoppedAt: 1.2)
        try at(302)
        try harness.client.suspend(reason: "user")
        try at(315)
        try harness.client.resume()
        try at(342)
        try bolusOnThePump(units: 1.5)

        try at(372)
        try anotherApp { _ in
            XCTAssertNil(try self.enactTempBasal(unitsPerHour: 0.6 * Self.profileRate, duration: .minutes(60)))
            otherAppTempRateIds.append(try XCTUnwrap(try self.harness.client.snapshot().basal.tempRateId))
        }
        try at(392)
        return PumpInUse(otherAppTempRateIds: otherAppTempRateIds, pumpScreenTempRateId: pumpScreenTempRateId)
    }

    @discardableResult
    private func bolusOnThePump(units: Double, stoppedAt delivered: Double? = nil) throws -> Int {
        try harness.client.startBolus(units: units, source: "pump")
        let bolusId = try harness.client.snapshot().bolus.bolusId
        if let delivered {
            try clock.advanceBoth(seconds: delivered / Self.bolusRate, ticks: 1)
            try harness.client.abortBolus(deliveredUnits: delivered)
        } else {
            try advanceUntilBolusFinishes(bolusId: bolusId)
        }
        return bolusId
    }

    /// Another app on the phone, paired with the pump before this one: it commands over Bluetooth and
    /// goes away, and comes back on its own key.
    private func anotherApp(_ commands: (FaketandemHarness.Driver) throws -> Void) throws {
        let driver: FaketandemHarness.Driver
        if let otherAppState {
            driver = startDriver(state: TandemPumpManagerState(rawValue: otherAppState))
        } else {
            driver = startDriver(state: try appState())
            try harness.pair(driver)
        }
        try commands(driver)
        otherAppState = driver.manager.state.rawValue
        try shutDownDriver()
    }

    /// The new manager setup builds: the host's schedule, which the pump's profile runs, and the
    /// history flags at their defaults.
    private func appState() throws -> TandemPumpManagerState {
        var state = TandemPumpManagerState(basalRateSchedule: try XCTUnwrap(BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)],
            timeZone: .current
        )))
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.featureFlags[.basalHistoryReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.settings.maxBolus = 10
        state.settings.maxTempBasalRate = 3
        return state
    }

    // MARK: - Setup

    /// As `TandemKitScanViewModel` runs it: pairing, Control-IQ turned off if the pump runs it, the
    /// onboarding writes and a sync, with no host.
    private func pairThisApp() throws -> FaketandemHarness.Driver {
        hostDelegatesFrom = delegates.count
        let driver = startDriver(state: try appState(), attachDelegate: false)
        try harness.pair(driver)
        let controlIQ = ResultBox<Bool>()
        driver.manager.controlIQNeedsTurningOffForSetup { controlIQ.set($0) }
        if try controlIQ.wait("the Control-IQ check", timeout: 60) {
            let turnedOff = ResultBox<Error?>()
            driver.manager.turnOffControlIQForSetup { turnedOff.set($0) }
            XCTAssertNil(try turnedOff.wait("turning Control-IQ off", timeout: 60), "Control-IQ turned off")
        }
        let onboarded = ResultBox<OnboardingSettingsFailure?>()
        driver.manager.applyOnboardingSettings { onboarded.set($0) }
        XCTAssertNil(try onboarded.wait("applyOnboardingSettings", timeout: 120), "the onboarding writes")
        let synced = ResultBox<Date?>()
        driver.manager.syncPumpData { synced.set($0) }
        XCTAssertNotNil(try synced.wait("setup's sync", timeout: syncTimeout), "setup's sync reached the pump")
        return driver
    }

    private final class ProgressLog {
        private let lock = NSLock()
        private var values: [Double] = []

        func append(_ value: Double) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var all: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    /// The Load Pump History step's Load, a minute after setup's sync, as a person reads the step.
    /// Returns the start of its window.
    @discardableResult
    private func loadHistory(_ driver: FaketandemHarness.Driver, file: StaticString = #filePath, line: UInt = #line) throws -> Date {
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        let since = clock.now.addingTimeInterval(-TandemPumpManager.setupHistoryLoadWindow)
        let progress = ProgressLog()
        let loaded = ResultBox<Error?>()
        driver.manager.loadHistoryForSetup(progress: progress.append, completion: { loaded.set($0) })
        XCTAssertNil(try loaded.wait("the setup history load", timeout: 300), "the load completes", file: file, line: line)
        XCTAssertEqual(progress.all.last, 1, "the progress reaches 100%: \(progress.all)", file: file, line: line)
        XCTAssertTrue(progress.all.allSatisfy { (0 ... 1).contains($0) }, "\(progress.all)", file: file, line: line)
        return since
    }

    /// The host takes the manager as Trio does, delegate then queue, and is handed what was held.
    private func adopt(_ driver: FaketandemHarness.Driver) {
        driver.manager.pumpManagerDelegate = driver.delegate
        driver.manager.delegateQueue = driver.delegateQueue
        driver.drainDelegate()
    }

    /// Until a tick has read the pump's log to its end and the report pass behind it has run.
    private func waitForHistoryPass(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try harness.client.snapshot().history.lastSequence
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy && !driver.manager.historyBackfillCoordinator.isTickRunning
        }
        let jobsDone = ResultBox<Void>()
        driver.bluetooth.ensureConnected { _ in jobsDone.set(()) }
        try jobsDone.wait("the history pass's command job", timeout: timeout)
        driver.drainDelegate()
    }

    /// The host's 5-minute loop. A command goes after the clocks move on: on a frozen clock, a tick the
    /// last sync started seems to start with the command, and takes its change as one it read past.
    private func syncEveryCycle(until minutes: Double) throws {
        let end = self.minutes(minutes)
        while clock.now < end {
            try advance(to: min(end, clock.now.addingTimeInterval(Self.cycle)))
            _ = try sync()
        }
    }

    // MARK: - What this app's host holds

    private var hostDelegates: ArraySlice<MockPumpManagerDelegate> {
        drainDelegate()
        return delegates.dropFirst(hostDelegatesFrom)
    }

    private var hostEvents: [NewPumpEvent] {
        hostDelegates.flatMap { $0.pumpEventBatches.flatMap(\.events) }
    }

    private var hostDoseEvents: [NewPumpEvent] {
        hostEvents.filter {
            switch $0.dose?.type {
            case .bolus?, .tempBasal?, .suspend?, .resume?: return true
            case .basal?, nil: return false
            }
        }
    }

    private var hostCorrections: [NewPumpEvent] {
        hostEvents.filter { $0.dose?.type == .tempBasal && HistoryLogSyncIdentifier.decode($0.raw)?.scheme == .logSequence }
    }

    private func hostOracles() -> (loop: LoopDoseStoreOracle, trio: TrioDoseStoreOracle) {
        let loop = LoopDoseStoreOracle()
        let trio = TrioDoseStoreOracle()
        for delegate in hostDelegates {
            _ = delegate.feed(loop, trio)
        }
        return (loop, trio)
    }

    private func assertNoDuplicates(_ loop: LoopDoseStoreOracle, _ trio: TrioDoseStoreOracle, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        loop.assertNoDuplicates(message, file: file, line: line)
        trio.assertNoDuplicates(message, file: file, line: line)
        trio.assertNoSameSecondBasalRows(message, file: file, line: line)
        XCTAssertNoThrow(try trio.basalSegments(clock: clock.now), "Trio's IOB runs", file: file, line: line)
    }

    /// Each finished bolus the pump started from `start` once in each host, permanent, at the pump's
    /// start and volume, and the host's total bolus insulin the pump's.
    private func assertHostsHoldThePumpsBoluses(
        from start: Date,
        _ loop: LoopDoseStoreOracle,
        _ trio: TrioDoseStoreOracle,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pumpBoluses = try timeline().boluses.filter { ($0.start ?? .distantPast) >= start }
        XCTAssertEqual(pumpBoluses.count, count, "the pump's boluses from \(start): \(pumpBoluses)", file: file, line: line)
        let stored = loop.doses.filter { $0.dose.type == .bolus }
        XCTAssertEqual(stored.count, pumpBoluses.count, "\(loop.doses.map(LoopDoseStoreOracle.describe))", file: file, line: line)
        for bolus in pumpBoluses {
            let pumpStart = try XCTUnwrap(bolus.start)
            guard let dose = stored.first(where: { abs($0.dose.startDate.timeIntervalSince(pumpStart)) <= 2 }) else {
                XCTFail("bolus \(bolus.bolusId) at \(pumpStart) is not in Loop: \(stored.map(LoopDoseStoreOracle.describe))", file: file, line: line)
                continue
            }
            XCTAssertFalse(dose.isMutable, "bolus \(bolus.bolusId) finalized", file: file, line: line)
            XCTAssertEqual(
                dose.dose.deliveredUnits ?? -1,
                try XCTUnwrap(bolus.deliveredUnits),
                accuracy: 0.0005,
                "bolus \(bolus.bolusId) at what the pump delivered",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(trio.boluses.count, pumpBoluses.count, "\(trio.boluses)", file: file, line: line)
        XCTAssertEqual(
            stored.reduce(0) { $0 + ($1.dose.deliveredUnits ?? 0) },
            pumpBoluses.reduce(0) { $0 + ($1.deliveredUnits ?? 0) },
            accuracy: 0.001,
            "the host counts the bolus insulin the pump delivered from \(start)",
            file: file,
            line: line
        )
    }

    /// Both hosts count the basal the closed BasalDelivery records from `start` delivered, give or take
    /// `residual`, what the host counts from a command that the pump runs from its next cycle.
    private func assertHostsCountThePumpsBasal(
        from start: Date,
        _ loop: LoopDoseStoreOracle,
        _ trio: TrioDoseStoreOracle,
        residual: Double = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let timeline = try timeline()
        let cycles = timeline.basalCycles.filter { $0.start >= start && $0.end <= clock.now }
        guard let first = cycles.first, let last = cycles.last else {
            return XCTFail("no closed BasalDelivery records from \(start)", file: file, line: line)
        }
        let scheduled: (Date) -> Double = { _ in Self.profileRate }
        let pump = timeline.netBasalUnits(from: first.start, to: last.end, scheduledRate: scheduled)
        let span = "from \(first.start) to \(last.end)"
        // Loop rebuilds the temp basal before a suspend without its deliveredUnits, so counts it in 0.05 U steps.
        let suspends = timeline.suspends.filter { $0.start > first.start && $0.start <= last.end }.count
        XCTAssertEqual(
            loop.netBasalUnits(from: first.start, to: last.end, scheduledRate: scheduled),
            pump + residual,
            accuracy: 0.005 + 0.025 * Double(suspends),
            "Loop counts the pump's basal \(span)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try trio.netBasalUnits(from: first.start, to: last.end, clock: clock.now, scheduledRate: scheduled),
            pump + residual,
            accuracy: 0.005,
            "Trio counts the pump's basal \(span)",
            file: file,
            line: line
        )
    }

    /// What the host counts and the pump did not deliver for a temp the host counts from its command
    /// at `date` and the pump runs from its next BasalDelivery record.
    private func residual(ofChangeAt date: Date, from old: Double, to new: Double, in timeline: PumpTimeline) throws -> Double {
        let cycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= date }, "no BasalDelivery record after \(date)")
        return (new - old) * cycle.start.timeIntervalSince(date) / .hours(1)
    }

    // MARK: - L1

    /// Six hours of a pump in use before pairing, loaded: every bolus, the suspend and resume, the
    /// other app's temps and the pump's own temp reach the host once, at the pump's times, and nothing
    /// older; both hosts count the pump's insulin over the window.
    func testL1_theLoadReportsTheWindowsDosesOnceAtThePumpsTimes() throws {
        let staged = try stagePumpInUse()
        let pairedAt = clock.now
        let driver = try pairThisApp()
        let since = try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try waitForHistoryPass(driver)
        let loaded = hostEvents.count
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        let runningTemp = HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: try XCTUnwrap(staged.otherAppTempRateIds.last))
        XCTAssertTrue(
            hostOracles().loop.normalizedDoses().contains { $0.syncIdentifier == runningTemp.hexadecimalString },
            "Loop counts the other app's running temp from its pump event until it has ended"
        )

        // Past the end of the other app's last temp.
        try syncEveryCycle(until: 447)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")
        let reportedAgain = hostEvents.dropFirst(loaded).filter { ($0.dose?.startDate ?? .distantFuture) < pairedAt }
        XCTAssertTrue(reportedAgain.isEmpty, "a later pass reports nothing loaded again: \(reportedAgain.map(\.dose))")

        let timeline = try timeline()
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "loaded history")
        try assertHostsHoldThePumpsBoluses(from: since, loop, trio, count: 4)
        XCTAssertEqual(
            Set(loop.doses.filter { $0.dose.type == .bolus }.compactMap(\.raw)),
            Set(timeline.boluses.filter { ($0.start ?? .distantPast) >= since }.map { HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: $0.bolusId) }),
            "under the identity any pump manager reports them under"
        )

        let pumpSuspend = try XCTUnwrap(timeline.suspends.last)
        XCTAssertGreaterThan(pumpSuspend.start, since)
        let suspends = loop.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.count, 1, "the suspend in the window, not the older one: \(suspends.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(suspends.first.map { $0.dose.startDate.timeIntervalSince(pumpSuspend.start) } ?? .infinity, 0, accuracy: 2, "at the pump's suspend")
        XCTAssertEqual(
            suspends.first.map { $0.dose.endDate.timeIntervalSince(pumpSuspend.resumed ?? .distantPast) } ?? .infinity,
            0,
            accuracy: 2,
            "to the pump's resume"
        )
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.count, 1)

        for tempRateId in staged.otherAppTempRateIds {
            let raw = HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId)
            let pump = try XCTUnwrap(timeline.tempRates.first { $0.tempRateId == tempRateId })
            XCTAssertEqual(trio.event(syncIdentifier: raw.hexadecimalString)?.isMutable, false, "Trio holds the other app's temp \(tempRateId)")
            guard let held = loop.pumpEventRow(raw: raw)?.dose else {
                XCTFail("the other app's temp \(tempRateId) is not in Loop under its temp rate id")
                continue
            }
            XCTAssertFalse(held.isMutable)
            XCTAssertEqual(held.startDate.timeIntervalSince(pump.start), 0, accuracy: 2, "temp \(tempRateId) at the pump's start")
            XCTAssertEqual(held.endDate.timeIntervalSince(try XCTUnwrap(pump.end)), 0, accuracy: 2, "temp \(tempRateId) to the pump's end")
            XCTAssertEqual(held.unitsPerHour, try XCTUnwrap(pump.rate), accuracy: 0.001)
        }

        let pumpScreenTemp = try XCTUnwrap(timeline.tempRates.first { $0.tempRateId == staged.pumpScreenTempRateId })
        let pumpScreenTempEnd = try XCTUnwrap(pumpScreenTemp.end)
        let pumpScreenCycles = timeline.basalCycles.filter { $0.source == 2 && $0.start >= pumpScreenTemp.start && $0.start <= pumpScreenTempEnd }
        let corrections = hostCorrections
        XCTAssertEqual(
            corrections.count,
            pumpScreenCycles.count,
            "one correction per BasalDelivery record of the temp set on the pump, and none else: \(corrections.map(\.dose))"
        )
        for (correction, cycle) in zip(corrections, pumpScreenCycles) {
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, cycle.rate, accuracy: 0.0005)
            XCTAssertEqual(correction.date.timeIntervalSince(cycle.start), 0, accuracy: 2)
            XCTAssertEqual(correction.dose?.wasProgrammedByPumpUI, true)
            XCTAssertNotNil(loop.assertPermanent(raw: correction.raw, "Loop keeps every correction"))
        }

        // Loaded finalized to its programmed end, the other app's temp is stored at Loop's first save
        // after that end, and only empty batches have followed it.
        XCTExpectFailure("Loop leaves a finalized temp out of IOB from a boundary past its end until its next save (AGENTS.md, Deleting the pump manager: still open)") {
            XCTAssertTrue(loop.normalizedDoses().contains { $0.syncIdentifier == runningTemp.hexadecimalString }, "Loop counts the other app's temp after its end")
        }
        loop.syncPumpEventsToInsulinDeliveryStore(now: clock.now)
        XCTAssertNotNil(loop.assertPermanent(raw: runningTemp, "at the host's next save"))

        let firstCycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= since })
        try assertHostsCountThePumpsBasal(from: firstCycle.start, loop, trio)
    }

    // MARK: - L2

    /// The same pump, not loaded: nothing from before pairing reaches the host, the other app's temp
    /// still running is corrected from the first BasalDelivery record after pairing, and what the pump
    /// does next is reported.
    func testL2_withoutTheLoadNothingFromBeforePairingIsReportedAndWhatFollowsIs() throws {
        let staged = try stagePumpInUse()
        let pairedAt = clock.now
        let driver = try pairThisApp()
        adopt(driver)
        _ = try sync()
        try syncEveryCycle(until: 404)
        try bolusOnThePump(units: 1.0)
        try syncEveryCycle(until: 412)
        try harness.client.suspend(reason: "user")
        try syncEveryCycle(until: 420)
        try harness.client.resume()
        try syncEveryCycle(until: 437)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let early = hostDoseEvents.filter { ($0.dose?.startDate ?? .distantFuture) < pairedAt }
        XCTAssertTrue(early.isEmpty, "nothing from before pairing: \(early.map(\.dose))")
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        for tempRateId in staged.otherAppTempRateIds {
            XCTAssertFalse(
                hostEvents.contains { $0.raw == HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId) },
                "the other app's temp \(tempRateId) is not reported"
            )
        }

        let timeline = try timeline()
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "not loaded")
        try assertHostsHoldThePumpsBoluses(from: pairedAt, loop, trio, count: 1)
        let pumpSuspend = try XCTUnwrap(timeline.suspends.last)
        let suspends = loop.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.count, 1, "only the suspend after pairing: \(suspends.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(suspends.first.map { $0.dose.startDate.timeIntervalSince(pumpSuspend.start) } ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(suspends.first.map { $0.dose.endDate.timeIntervalSince(pumpSuspend.resumed ?? .distantPast) } ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.count, 1)

        let otherAppCycles = timeline.basalCycles.filter { $0.source == 2 && $0.start >= pairedAt }
        let corrections = hostCorrections
        XCTAssertEqual(
            corrections.count,
            otherAppCycles.count,
            "one correction per BasalDelivery record of the other app's temp after pairing: \(corrections.map(\.dose))"
        )
        for (correction, cycle) in zip(corrections, otherAppCycles) {
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, cycle.rate, accuracy: 0.0005)
            XCTAssertEqual(correction.date.timeIntervalSince(cycle.start), 0, accuracy: 2)
        }

        let firstCycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= pairedAt })
        try assertHostsCountThePumpsBasal(from: firstCycle.start, loop, trio)
    }

    // MARK: - L3

    /// Six and a half hours of scheduled basal and a few records that are not doses: the load reads it
    /// to the end, compares every BasalDelivery record in the window, and reports nothing.
    func testL3_aPumpWithOnlyScheduledBasalLoadsToTheEndAndReportsNothing() throws {
        try pairing(at: 392)
        try runBasalCycle()
        try at(97)
        try harness.client.appendHistory(type: "AlarmActivated", secondsAgo: 0, data: ["alarmId": 2])
        try at(99)
        try harness.client.appendHistory(type: "AlarmCleared", secondsAgo: 0, data: ["alarmId": 2])
        try at(203)
        for type in ["CartridgeFilled", "TubingFilled", "CannulaFilled"] {
            try harness.client.appendHistory(type: type, secondsAgo: 0, data: [:])
        }
        try at(392)
        let driver = try pairThisApp()
        let since = try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try syncEveryCycle(until: 412)
        try waitForHistoryPass(driver)

        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")
        XCTAssertTrue(hostDoseEvents.isEmpty, "no dose, correction, suspend or resume: \(hostDoseEvents.map(\.dose))")
        XCTAssertFalse(hostEvents.contains { $0.type == .alarm }, "an alarm in history is not a standing one")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "\(driver.manager.loggedBasalDifferences)")
        let timeline = try timeline()
        let lastClosed = try XCTUnwrap(timeline.basalCycles.last { $0.end <= clock.now })
        XCTAssertGreaterThanOrEqual(driver.manager.state.reportedBasal.reconciledThrough.map(Int.init) ?? 0, lastClosed.sequence)
        let compared = driver.manager.reconciliationLog.passes.compactMap(\.basal?.matched).reduce(0, +)
        let window = timeline.basalCycles.filter { $0.start >= since && $0.end <= clock.now }
        XCTAssertGreaterThanOrEqual(compared, window.count, "every BasalDelivery record in the window is compared, not skipped")
        let (loop, trio) = hostOracles()
        XCTAssertTrue(loop.doses.isEmpty, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(trio.events.filter { !$0.isScheduledBasal }.isEmpty, "\(trio.events)")
    }

    // MARK: - L4

    /// A pump just turned on, its log empty: pairing, the load and the syncs after it succeed at once,
    /// and the first doses, the app's and the pump's, each reach the host once, never again from history.
    func testL4_aPumpWithAnEmptyLogLoadsAtOnceAndItsFirstDosesAreReportedOnce() throws {
        XCTAssertTrue(try harness.client.history().isEmpty, "a log with no record")
        let driver = try pairThisApp()
        let mark = try harness.client.snapshot().requestLog.lastSeq
        XCTAssertTrue(try harness.client.history().isEmpty, "the onboarding wrote nothing the pump did not hold")
        try loadHistory(driver)
        let statusReads = try harness.requestsSeen(since: mark).filter { $0.message == "HistoryLogStatusRequest" }.count
        XCTAssertEqual(statusReads, 1, "loaded on its first tick, with no retry")
        adopt(driver)
        _ = try sync()
        try waitForHistoryPass(driver)
        XCTAssertTrue(hostDoseEvents.isEmpty, "\(hostDoseEvents.map(\.dose))")

        try at(3)
        XCTAssertNil(try enactBolus(units: 1.0))
        try advanceUntilBolusFinishes(bolusId: try XCTUnwrap(driver.manager.state.bolusDose?.bolusId))
        try syncEveryCycle(until: 8)
        try at(8.5)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 2 * Self.profileRate, duration: .minutes(30)))
        try syncEveryCycle(until: 14)
        try at(14.5)
        XCTAssertNil(try suspendDelivery())
        try syncEveryCycle(until: 24)
        try at(24.5)
        XCTAssertNil(try resumeDelivery())
        try syncEveryCycle(until: 31)
        try at(31.5)
        try bolusOnThePump(units: 0.5)
        try syncEveryCycle(until: 51)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "an empty log's first doses")
        try assertHostsHoldThePumpsBoluses(from: stagingStart, loop, trio, count: 2)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .tempBasal }.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .suspend }.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(trio.tempBasals.count, 1)
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.count, 1)
        XCTAssertTrue(hostCorrections.isEmpty, "\(hostCorrections.map(\.dose))")
        // Loop rebuilds the temp basal before a suspend without its deliveredUnits, so counts it in 0.05 U steps.
        try timeline().assertMatches(loop, tolerance: PumpTimeline.Tolerance(units: 0.025), "every dose once, at the pump's times")
    }

    // MARK: - L5

    /// A pump just turned on with its clock two days behind and a few records that are not doses:
    /// setup sets its clock and loads its history, reports nothing from it, and the pump's first bolus
    /// after reaches the host once at its time.
    func testL5_aPumpWithOnlyAFewRecordsAndAWrongClockLoadsAndReportsNothing() throws {
        try pairing(at: 20)
        let behind: TimeInterval = .hours(51) + .minutes(17)
        try harness.client.setPumpTimeOnThePump(deltaSeconds: -behind)
        try at(5)
        for type in ["CartridgeFilled", "TubingFilled", "CannulaFilled"] {
            try harness.client.appendHistory(type: type, secondsAgo: 0, data: [:])
        }
        try at(8)
        try harness.client.appendHistory(type: "AlarmActivated", secondsAgo: 0, data: ["alarmId": 2])
        try at(9)
        try harness.client.appendHistory(type: "AlarmCleared", secondsAgo: 0, data: ["alarmId": 2])
        try at(20)
        XCTAssertLessThan(try harness.client.history().count, 10, "a near-empty log")
        let driver = try pairThisApp()
        try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try waitForHistoryPass(driver)
        XCTAssertTrue(hostDoseEvents.isEmpty, "\(hostDoseEvents.map(\.dose))")
        XCTAssertEqual(driver.delegate.clockAdjustments.count, 1)
        XCTAssertEqual(driver.delegate.clockAdjustments.first ?? 0, behind, accuracy: 5, "moved forward what it was behind")
        XCTAssertEqual(driver.manager.state.pumpClockOffset, 0, accuracy: 5)

        try at(27)
        try bolusOnThePump(units: 1.0)
        try syncEveryCycle(until: 37)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "a near-empty log")
        try assertHostsHoldThePumpsBoluses(from: minutes(20), loop, trio, count: 1)
        XCTAssertEqual(hostDoseEvents.count, 1, "\(hostDoseEvents.map(\.dose))")
    }

    // MARK: - L6

    /// Loaded, a pump bolus, a suspend and another app's running temp; then the app's first bolus, a
    /// temp that replaces the other app's, a suspend and a resume: each reported once under its own
    /// identity, none again by the history passes after, and both hosts count the pump's insulin.
    func testL6_theFirstLiveDosesAfterALoadAreReportedOnce() throws {
        try pairing(at: 77)
        try runBasalCycle()
        try at(12)
        try bolusOnThePump(units: 1.0)
        try at(32)
        try harness.client.suspend(reason: "user")
        try at(40)
        try harness.client.resume()
        try at(62)
        var inheritedTempRateId = 0
        try anotherApp { _ in
            XCTAssertNil(try self.enactTempBasal(unitsPerHour: 0.6 * Self.profileRate, duration: .minutes(60)))
            inheritedTempRateId = try XCTUnwrap(try self.harness.client.snapshot().basal.tempRateId)
        }
        try at(77)
        let driver = try pairThisApp()
        let since = try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try waitForHistoryPass(driver)
        let loaded = hostEvents.count

        try at(82)
        XCTAssertNil(try enactBolus(units: 1.0))
        try advanceUntilBolusFinishes(bolusId: try XCTUnwrap(driver.manager.state.bolusDose?.bolusId))
        try syncEveryCycle(until: 87)
        try at(87.5)
        let appTempRate = 2 * Self.profileRate
        XCTAssertNil(try enactTempBasal(unitsPerHour: appTempRate, duration: .minutes(30)))
        try syncEveryCycle(until: 97)
        try at(97.5)
        XCTAssertNil(try suspendDelivery())
        try syncEveryCycle(until: 107)
        try at(107.5)
        XCTAssertNil(try resumeDelivery())
        try syncEveryCycle(until: 137)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let timeline = try timeline()
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        let live = hostEvents.dropFirst(loaded).filter { $0.dose?.isMutable == false && ($0.dose?.startDate ?? .distantPast) < minutes(77) }
        XCTAssertTrue(live.isEmpty, "nothing loaded is reported again: \(live.map(\.dose))")
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "live doses after a load")
        try assertHostsHoldThePumpsBoluses(from: since, loop, trio, count: 2)
        let suspends = loop.doses.filter { $0.dose.type == .suspend }.sorted { $0.dose.startDate < $1.dose.startDate }
        XCTAssertEqual(suspends.count, 2, "the loaded one and the app's: \(suspends.map(LoopDoseStoreOracle.describe))")
        for (stored, pump) in zip(suspends, timeline.suspends) {
            XCTAssertEqual(stored.dose.startDate.timeIntervalSince(pump.start), 0, accuracy: 2)
            XCTAssertEqual(stored.dose.endDate.timeIntervalSince(pump.resumed ?? .distantPast), 0, accuracy: 2)
        }
        XCTAssertEqual(trio.suspends.count, 2)
        XCTAssertEqual(trio.resumes.count, 2)
        XCTAssertNotNil(trio.event(syncIdentifier: HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: inheritedTempRateId).hexadecimalString))
        XCTAssertEqual(trio.tempBasals.count, 2, "the other app's and this app's: \(trio.tempBasals)")
        XCTAssertTrue(hostCorrections.isEmpty, "\(hostCorrections.map(\.dose))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "\(driver.manager.loggedBasalDifferences)")

        let inheritedRate = 0.6 * Self.profileRate
        let inherited = try XCTUnwrap(timeline.tempRates.first { $0.tempRateId == inheritedTempRateId })
        let appTemp = try XCTUnwrap(loop.doses.first { $0.dose.type == .tempBasal && abs($0.dose.unitsPerHour - appTempRate) < 0.001 })
        let residual = try residual(ofChangeAt: inherited.start, from: Self.profileRate, to: inheritedRate, in: timeline)
            + residual(ofChangeAt: appTemp.dose.startDate, from: inheritedRate, to: appTempRate, in: timeline)
        let firstCycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= since })
        try assertHostsCountThePumpsBasal(from: firstCycle.start, loop, trio, residual: residual)
    }

    // MARK: - L7

    /// A bolus on the pump's screen still delivering through pairing and the load: reported once, when
    /// history reads its completion, at the pump's start and volume.
    func testL7_aBolusDeliveringThroughTheLoadIsReportedOnceItCompletes() throws {
        try pairing(at: 14)
        try runBasalCycle()
        try at(12)
        try harness.client.startBolus(units: 3.0, durationSeconds: 600, source: "pump")
        let bolusId = try harness.client.snapshot().bolus.bolusId
        try at(14)
        let driver = try pairThisApp()
        try loadHistory(driver)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the bolus still delivers after the load")
        adopt(driver)
        _ = try sync()
        try syncEveryCycle(until: 32)
        try waitForHistoryPass(driver)
        XCTAssertFalse(try harness.client.snapshot().bolus.active)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "a bolus through the load")
        try assertHostsHoldThePumpsBoluses(from: stagingStart, loop, trio, count: 1)
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        XCTAssertNotNil(loop.assertPermanent(raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolusId)))
        XCTAssertTrue(driver.manager.state.bolusReportLedger.unreported.isEmpty, "the boundary is no longer held for it")
    }

    // MARK: - L8

    /// A pump suspended on its screen before pairing and still suspended when paired, resumed from the
    /// app after setup: the host holds one suspend, from the pump's stop to the resume, and counts the
    /// pump's basal.
    func testL8_aPumpSuspendedWhenPairedIsSuspendedFromItsStop() throws {
        try pairing(at: 52)
        try runBasalCycle()
        try at(12)
        try bolusOnThePump(units: 1.0)
        try at(32)
        try harness.client.suspend(reason: "user")
        try at(52)
        let driver = try pairThisApp()
        let since = try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try syncEveryCycle(until: 62)
        try at(62.5)
        XCTAssertNil(try resumeDelivery())
        try syncEveryCycle(until: 82)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let timeline = try timeline()
        let pumpSuspend = try XCTUnwrap(timeline.suspends.first)
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "suspended when paired")
        try assertHostsHoldThePumpsBoluses(from: since, loop, trio, count: 1)
        let suspends = loop.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(suspends.first.map { $0.dose.endDate.timeIntervalSince(pumpSuspend.resumed ?? .distantPast) } ?? .infinity, 0, accuracy: 2, "to the resume")
        XCTAssertEqual(trio.suspends.count, 1, "\(trio.suspends)")
        XCTAssertEqual(trio.resumes.count, 1, "\(trio.resumes)")
        let firstCycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= since })
        // Setup's sync reports the suspend at detection, its record predating tracking, and the load's
        // pass matches the record to that: the host counts the schedule over the stop before pairing.
        try XCTExpectFailure("A pump suspended when paired is reported suspended from setup's sync, not from its stop") {
            XCTAssertEqual(suspends.first.map { $0.dose.startDate.timeIntervalSince(pumpSuspend.start) } ?? .infinity, 0, accuracy: 2, "from the pump's stop")
            try assertHostsCountThePumpsBasal(from: firstCycle.start, loop, trio)
        }
    }

    // MARK: - L9

    /// A pump whose history log does not answer: the load fails after its retries rather than hanging,
    /// and Try Again loads once the pump answers.
    func testL9_aLoadThatCannotReadThePumpsHistoryFailsAndLoadsOnTryAgain() throws {
        try pairing(at: 22)
        try runBasalCycle()
        try at(12)
        try bolusOnThePump(units: 1.0)
        try at(22)
        let driver = try pairThisApp()
        var unanswered = FaketandemFaultSpec(.dropResponse, message: "HistoryLogStatusRequest")
        unanswered.every = true
        let fault = try XCTUnwrap(try harness.client.armFault(unanswered))
        let mark = try harness.client.snapshot().requestLog.lastSeq

        let failed = ResultBox<Error?>()
        driver.manager.loadHistoryForSetup(progress: { _ in }, completion: { failed.set($0) })
        let error = try failed.wait("the setup history load", timeout: 120)
        XCTAssertEqual(error as? SetupHistoryLoadError, .historyUnreadable)
        let statusReads = try harness.requestsSeen(since: mark).filter { $0.message == "HistoryLogStatusRequest" }.count
        XCTAssertEqual(statusReads, TandemPumpManager.setupHistoryLoadFailureLimit, "one read a tick, until the limit")

        try harness.client.clearFault(id: fault.id)
        try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try waitForHistoryPass(driver)
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "loaded on Try Again")
        try assertHostsHoldThePumpsBoluses(from: stagingStart, loop, trio, count: 1)
    }

    // MARK: - L10

    /// An hour of Control-IQ before pairing, still on when paired: setup turns it off, and the load
    /// reports a correction for each BasalDelivery record off the schedule, so both hosts count the
    /// pump's basal.
    func testL10_controlIQBeforePairingIsCorrectedFromItsBasalDeliveryRecords() throws {
        try pairing(at: 62)
        try runBasalCycle()
        try at(2)
        try harness.client.setState(["closed_loop_enabled": true])
        let rates = [1.4, 0.4, 0.85, 2.2, 0.0, 1.0, 1.8, 0.6, 0.85, 1.2, 0.3, 1.6]
        for (index, rate) in rates.enumerated() {
            try harness.client.setState(["controliq_algorithm_rate": rate])
            try at(2 + Double(index + 1) * 5)
        }
        let driver = try pairThisApp()
        XCTAssertEqual(try harness.client.snapshot().basalCycle?.pcm, 1, "setup turned Control-IQ off")
        let since = try loadHistory(driver)
        adopt(driver)
        _ = try sync()
        try syncEveryCycle(until: 82)
        try waitForHistoryPass(driver)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")
        XCTAssertFalse(driver.manager.state.useControlIQ)

        let timeline = try timeline()
        let controlIQCycles = timeline.basalCycles.filter { $0.source == 3 && $0.end <= clock.now }
        XCTAssertEqual(controlIQCycles.count, rates.count, "\(timeline.basalCycles)")
        let offTheSchedule = controlIQCycles.filter { abs($0.rate - Self.profileRate) > 0.01 }
        let corrections = hostCorrections
        XCTAssertEqual(corrections.count, offTheSchedule.count, "one correction per Control-IQ record off the schedule: \(corrections.map(\.dose))")
        for (correction, cycle) in zip(corrections, offTheSchedule) {
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, cycle.rate, accuracy: 0.0005)
            XCTAssertEqual(correction.date.timeIntervalSince(cycle.start), 0, accuracy: 2)
            XCTAssertEqual(correction.dose?.automatic, true)
        }
        let (loop, trio) = hostOracles()
        assertNoDuplicates(loop, trio, "Control-IQ before pairing")
        let firstCycle = try XCTUnwrap(timeline.basalCycles.first { $0.start >= since })
        try assertHostsCountThePumpsBasal(from: firstCycle.start, loop, trio)
    }
}
