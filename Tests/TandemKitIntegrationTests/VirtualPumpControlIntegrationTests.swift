import LoopKit
@testable import TandemKit
import XCTest
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif

/// The control channel against a driver in this process, as the Trio tests use it against the
/// driver inside Trio: what it reads back must be what the delegate was given.
final class VirtualPumpControlIntegrationTests: FaketandemIntegrationTestCase {
    private var server: VirtualPumpControl.Server?
    private var control: VirtualPumpControl.Client?

    override func tearDownWithError() throws {
        control?.close()
        server?.stop()
        try super.tearDownWithError()
    }

    func testABolusMadeThroughTheChannelReadsBackAsTheDelegateReceivedIt() throws {
        let driver = try pairThroughTheChannel()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        _ = try send(.init(command: .bolus, units: 1.0))

        let finalized = try IntegrationWait.value("a finalized bolus through the channel", timeout: 300) {
            _ = try send(.init(command: .sync))
            let batches = try XCTUnwrap(send(.init(command: .pumpEventBatches)).batches)
            return batches.flatMap(\.pumpEvents).first { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.deliveredUnits, 1.0)

        let oracle = try assertChannelReadsBackWhatTheDelegateReceived(driver)
        XCTAssertEqual(oracle.boluses.map(\.bolusAmount), [1.0])
    }

    func testBasalCommandsMadeThroughTheChannelReadBackAsTheDelegateReceivedThem() throws {
        let driver = try pairThroughTheChannel(stageBasalScheduleSync: false)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)

        _ = try send(.init(command: .syncBasalSchedule, basalSchedule: [RepeatingScheduleValue(startTime: 0, value: 1.0)]))
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)
        XCTAssertEqual(try harness.client.snapshot().idpProfiles?.first?.segments.map(\.basalRate), [1000])
        _ = try send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        _ = try send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))
        _ = try send(.init(command: .suspend))
        _ = try send(.init(command: .resume))

        let oracle = try assertChannelReadsBackWhatTheDelegateReceived(driver)
        let temps = oracle.events.filter { $0.type == .tempBasal && !$0.isScheduledBasal }
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5], "\(oracle.events)")
        XCTAssertEqual(temps.map(\.isMutable), [false])
        XCTAssertEqual(oracle.events.filter { $0.type == .pumpSuspend || $0.type == .pumpResume }.map(\.type), [.pumpSuspend, .pumpResume])
    }

    func testOnboardingThroughTheChannelWritesTheSetupSettingsToThePump() throws {
        // What the setup screen builds from the host's settings before it pairs.
        let setup = TandemPumpManagerState(
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!,
            maxBasalRateUnitsPerHour: 2,
            maxBolusUnits: 10
        )
        let driver = try pairThroughTheChannel(state: setup, stageBasalScheduleSync: false)

        _ = try send(.init(command: .applyOnboardingSettings))

        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)
        let pump = try harness.client.snapshot()
        XCTAssertEqual(pump.idpProfiles?.first?.segments.map(\.basalRate), [1000])
        XCTAssertEqual(pump.limits?.maxBasalMilliunits, 2000)
        XCTAssertEqual(pump.limits?.maxBolusMilliunits, 10000)
    }

    func testABolusCancelledThroughTheChannelIsFinalizedAtWhatThePumpDelivered() throws {
        let driver = try pairThroughTheChannel()
        try harness.client.setState(["bolus_rate_units_per_second": 0.05])
        _ = try send(.init(command: .bolus, units: 2.0))
        try IntegrationWait.until("the pump to have delivered part of the bolus", timeout: 60) {
            try self.harness.client.snapshot().bolus.unitsDelivered >= 0.2
        }

        _ = try send(.init(command: .cancelBolus))

        let delivered = try XCTUnwrap(harness.client.snapshot().lastBolus?.deliveredUnits)
        XCTAssertLessThan(delivered, 2.0)
        let oracle = try assertChannelReadsBackWhatTheDelegateReceived(driver)
        XCTAssertEqual(oracle.boluses.map(\.isMutable), [false])
        let finalized = try XCTUnwrap(driver.delegate.pumpEventBatches.flatMap(\.events).last { $0.dose?.type == .bolus })
        XCTAssertEqual(finalized.dose?.isMutable, false)
        // On the wall clock the pump stops between milliunits, and reports whole ones.
        XCTAssertEqual(finalized.dose?.deliveredUnits ?? -1, delivered, accuracy: 0.001)
    }

    // MARK: - Helpers

    /// Trio's clock: doses are finalized on real time, as they would be in the app.
    private func pairThroughTheChannel(
        state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:]),
        stageBasalScheduleSync: Bool = true
    ) throws -> FaketandemHarness.Driver {
        let driver = makeDriver(state: state, clock: SystemClock(), stageBasalScheduleSync: stageBasalScheduleSync)
        let manager = driver.manager
        let server = try VirtualPumpControl.Server { manager }
        self.server = server
        control = try VirtualPumpControl.Client(port: server.port)

        var key = Data(count: 32)
        for index in key.indices {
            key[index] = UInt8.random(in: .min ... .max)
        }
        _ = try harness.control.setLongTermKey(key)
        let paired = try send(.init(command: .pair, code: FaketandemHarness.pairingCode, longTermKey: key.hexadecimalString))
        XCTAssertEqual(paired.status?.onboarded, true)
        _ = try send(.init(command: .sync))
        return driver
    }

    /// Returns a Trio oracle fed from the channel.
    private func assertChannelReadsBackWhatTheDelegateReceived(
        _ driver: FaketandemHarness.Driver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TrioDoseStoreOracle {
        // The driver may still be reporting, from a qualifying event the last command raised, and the
        // channel logs a batch just before the delegate gets it: compared once both logs hold the same.
        var batches: [VirtualPumpControl.Batch] = []
        var received: [MockPumpManagerDelegate.PumpEventBatch] = []
        try? IntegrationWait.until("the channel and the delegate to log the same batches", timeout: 30) {
            driver.drainDelegate()
            batches = try XCTUnwrap(send(.init(command: .pumpEventBatches)).batches)
            received = driver.delegate.pumpEventBatches
            return batches.map(\.pumpEvents) == received.map(\.events) && batches.allSatisfy(\.completed)
        }
        XCTAssertEqual(batches.map(\.pumpEvents), received.map(\.events), file: file, line: line)
        XCTAssertEqual(batches.map(\.replacePendingEvents), received.map(\.replacePendingEvents), file: file, line: line)
        XCTAssertEqual(batches.map(\.lastReconciliation), received.map(\.lastReconciliation), file: file, line: line)
        XCTAssertTrue(batches.allSatisfy { $0.completed && $0.delegateError == nil }, file: file, line: line)

        let oracle = TrioDoseStoreOracle()
        for batch in batches {
            oracle.addPumpEvents(
                batch.pumpEvents,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: batch.hostNow
            )
        }
        return oracle
    }

    /// Off the main thread: the driver finishes some work on the main queue, which this pumps.
    private func send(_ request: VirtualPumpControl.Request) throws -> VirtualPumpControl.Response {
        let control = try XCTUnwrap(control)
        let box = ResultBox<Result<VirtualPumpControl.Response, Error>>()
        DispatchQueue.global().async {
            box.set(Result { try control.send(request) })
        }
        return try box.wait("control \(request.command)", timeout: 300).get()
    }
}
