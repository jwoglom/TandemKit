@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// A manager no host has adopted is a setup flow's. One a flow left behind went on reconnecting to
/// the pump it had paired and held the pump's one link against every attempt after it (#603).
final class UnadoptedManagerIntegrationTests: FaketandemIntegrationTestCase {
    /// Long enough for the reconnect the old driver made at the drop, and its first two retries.
    private var reconnectWindow: TimeInterval {
        FaketandemHarness.reconnectRetryDelays.prefix(2).reduce(0, +) + 3
    }

    func testAnOnboardedManagerNoHostAdoptedDoesNotTakeThePumpBackAfterADrop() throws {
        let orphan = harness.makeDriver(attachDelegate: false)
        addTeardownBlock { try self.harness.shutDown(orphan) }
        try harness.pair(orphan)
        try IntegrationWait.until("the orphan to hold the pump", timeout: 30) {
            try orphan.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        try harness.control.disconnectPump()
        try IntegrationWait.until("the orphan to see the link go", timeout: 30) { !orphan.manager.state.isConnected }

        let deadline = Date().addingTimeInterval(reconnectWindow)
        while Date() < deadline {
            XCTAssertFalse(orphan.manager.state.isConnected, "a manager no host adopted reconnected on its own")
            IntegrationWait.pump()
        }
        let connections = try harness.requestLog(since: logStart).filter { $0.kind == "connection" }.map(\.connected)
        XCTAssertEqual(connections, [false], "the pump saw only the drop")

        // The next attempt, a manager the host adopts with the same key, gets the pump.
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState = orphan.manager.state.pumpState
        state.hasSyncedBasalRateSchedule = true
        let adopted = harness.makeDriver(state: state)
        addTeardownBlock { try self.harness.shutDown(adopted) }

        XCTAssertNotNil(try harness.sync(adopted), "the adopted manager's first sync must reach the pump")
        XCTAssertTrue(adopted.manager.state.isConnected)
        XCTAssertTrue(adopted.delegate.errors.isEmpty, "\(adopted.delegate.errors)")
    }
}
