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
        // Trio's clock: the bolus is finalized on real time, as it would be in the app.
        let driver = makeDriver(clock: SystemClock())
        let manager = driver.manager
        let server = try VirtualPumpControl.Server { manager }
        self.server = server
        let control = try VirtualPumpControl.Client(port: server.port)
        self.control = control

        var key = Data(count: 32)
        for index in key.indices {
            key[index] = UInt8.random(in: .min ... .max)
        }
        _ = try harness.control.setLongTermKey(key)
        let paired = try send(.init(command: .pair, code: FaketandemHarness.pairingCode, longTermKey: key.hexadecimalString))
        XCTAssertEqual(paired.status?.onboarded, true)
        _ = try send(.init(command: .sync))
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        _ = try send(.init(command: .bolus, units: 1.0))

        let finalized = try IntegrationWait.value("a finalized bolus through the channel", timeout: 300) {
            _ = try send(.init(command: .sync))
            let batches = try XCTUnwrap(send(.init(command: .pumpEventBatches)).batches)
            return batches.flatMap(\.pumpEvents).first { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.deliveredUnits, 1.0)

        driver.drainDelegate()
        let batches = try XCTUnwrap(send(.init(command: .pumpEventBatches)).batches)
        XCTAssertEqual(batches.map(\.pumpEvents), driver.delegate.pumpEventBatches.map(\.events))
        XCTAssertEqual(batches.map(\.replacePendingEvents), driver.delegate.pumpEventBatches.map(\.replacePendingEvents))
        XCTAssertEqual(batches.map(\.lastReconciliation), driver.delegate.pumpEventBatches.map(\.lastReconciliation))
        XCTAssertTrue(batches.allSatisfy { $0.completed && $0.delegateError == nil })

        let fromChannel = TrioDoseStoreOracle()
        for batch in batches {
            fromChannel.addPumpEvents(
                batch.pumpEvents,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: batch.hostNow
            )
        }
        let fromDelegate = TrioDoseStoreOracle()
        driver.delegate.feed(fromDelegate)
        XCTAssertEqual(fromChannel.events, fromDelegate.events)
        XCTAssertEqual(fromChannel.boluses.map(\.bolusAmount), [1.0])
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
