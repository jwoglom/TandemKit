@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

final class ReconnectIntegrationTests: FaketandemIntegrationTestCase {
    private func authOpcodes(since: Int) throws -> [Int] {
        try harness.requestsSeen(since: since).filter { $0.characteristic == "Authorization" }.map(\.opcode)
    }

    func testPumpSideDropIsFollowedByAQuickReconnect() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        let secret = try XCTUnwrap(driver.manager.state.pumpState.derivedSecret)
        let keyBefore = try harness.control.pairingStatus().longTermKey
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        try harness.control.disconnectPump()

        let log = try IntegrationWait.value("pump to log the drop and a new connection", timeout: 30) {
            let entries = try harness.requestLog(since: logStart).filter { $0.kind == "connection" }
            return entries.map(\.connected) == [false, true] ? entries : nil
        }
        XCTAssertEqual(log.count, 2)
        try IntegrationWait.until("driver to be connected and the pump authenticated", timeout: 60) {
            try driver.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }

        XCTAssertEqual(driver.manager.state.pumpState.derivedSecret, secret, "quick reconnect keeps the cached key")
        XCTAssertEqual(try harness.control.pairingStatus().longTermKey, keyBefore)
        XCTAssertEqual(
            try authOpcodes(since: logStart),
            [Int(Jpake3SessionKeyRequest.props.opCode), Int(Jpake4KeyConfirmationRequest.props.opCode)],
            "a reconnect with a cached key goes straight to JPAKE round 3"
        )

        XCTAssertNotNil(try harness.sync(driver), "the new session must serve commands")
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")
    }

    /// The pump goes out of range long enough for the reconnect to fail, then comes back. Nothing
    /// tells the driver, and the host's sync is throttled, so the driver has to keep trying itself
    /// (jwoglom/tandemkit-stress#4).
    func testRadioOutageIsFollowedByAReconnectWithoutASync() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        addTeardownBlock { try self.harness.client.armFault(FaketandemFaultSpec(.radioOn)) }

        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))

        let retryBudget = driver.bluetooth.reconnectRetryDelays.prefix(3).reduce(0, +) + 30
        try IntegrationWait.until("the driver to reconnect on its own", timeout: retryBudget) {
            try driver.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
        XCTAssertEqual(
            try authOpcodes(since: logStart),
            [Int(Jpake3SessionKeyRequest.props.opCode), Int(Jpake4KeyConfirmationRequest.props.opCode)]
        )
        XCTAssertNotNil(try harness.sync(driver), "the new session must serve commands")
    }

    /// A weak-signal stretch cuts every handshake in a row (#565).
    func testRadioDropsMidHandshakeDoNotStopTheAutomaticReconnects() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        addTeardownBlock { try self.harness.client.armFault(FaketandemFaultSpec(.radioOn)) }
        // Unanswered, so each handshake is still waiting on round 3 when the radio goes.
        var unanswered = FaketandemFaultSpec(.dropResponse, message: "Jpake3SessionKeyRequest")
        unanswered.every = true
        let fault = try XCTUnwrap(try harness.client.armFault(unanswered))
        var logStart = try harness.client.snapshot().requestLog.lastSeq
        try harness.control.disconnectPump()

        let retryBudget = driver.bluetooth.reconnectRetryDelays.prefix(4).reduce(0, +) + 30
        for _ in 0 ..< TandemBluetoothManager.jpakeFailureLimit {
            try IntegrationWait.until("the driver's next handshake", timeout: retryBudget) {
                try harness.requestsSeen(since: logStart).contains { $0.message == "Jpake3SessionKeyRequest" }
            }
            logStart = try harness.client.snapshot().requestLog.lastSeq
            try harness.client.armFault(FaketandemFaultSpec(.radioOff))
            try IntegrationWait.until("the pump to lose the link", timeout: 10) {
                try !harness.client.snapshot().connection.connected
            }
            try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        }
        XCTAssertFalse(driver.bluetooth.isJpakeFailureLimitReached)
        XCTAssertNotEqual(driver.manager.connectionIssue, .handshakeFailing)

        try harness.client.clearFault(id: fault.id)
        try IntegrationWait.until("the driver to reconnect on its own", timeout: retryBudget) {
            try driver.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
    }

    /// As a second host on the pump does (#400): a far-end drop at round 3, every time.
    func testThePumpEndingEveryHandshakeStopsTheAutomaticReconnects() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        var cutOff = FaketandemFaultSpec(.disconnect, message: "Jpake3SessionKeyRequest")
        cutOff.after = "request"
        cutOff.every = true
        try harness.client.armFault(cutOff)

        try harness.control.disconnectPump()

        try IntegrationWait.until("the handshake failure limit", timeout: 60) {
            driver.bluetooth.isJpakeFailureLimitReached
        }
        XCTAssertEqual(driver.manager.connectionIssue, .handshakeFailing)
    }

    /// Whatever the pump did out of range reaches the host only through a sync, and the host's next
    /// poll can be minutes off (#351). The reconnect retry or a job of the driver's own lands it.
    func testAReconnectAfterAnOutageSyncsAndReportsToTheHost() throws {
        let driver = makeDriver()
        let outage = try pairSyncAndGoOutOfRange(driver)
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))

        let retryBudget = driver.bluetooth.reconnectRetryDelays.prefix(3).reduce(0, +) + 30
        try assertSyncedOnItsOwn(driver, after: outage, timeout: retryBudget)
    }

    /// A history tick or report reconnecting first left the retry nothing to do, so neither synced.
    func testACommandThatReconnectsAfterAnOutageIsFollowedByASync() throws {
        let driver = makeDriver()
        let outage = try pairSyncAndGoOutOfRange(driver)
        // Stops the driver's own reconnects, so only the command below can bring the link back.
        for _ in 0 ..< TandemBluetoothManager.jpakeFailureLimit {
            driver.bluetooth.recordJpakeFailure()
        }
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))

        let connected = ResultBox<Error?>()
        driver.bluetooth.ensureConnected { connected.set($0) }
        XCTAssertNil(try connected.wait("the command's connect", timeout: 60))
        try assertSyncedOnItsOwn(driver, after: outage, timeout: 60)
    }

    private struct Outage {
        let reconciliationBefore: Date
        let batchesBefore: Int
        let logStart: Int
    }

    /// Leaves the radio off; the caller turns it back on.
    private func pairSyncAndGoOutOfRange(_ driver: FaketandemHarness.Driver) throws -> Outage {
        try harness.pair(driver)
        addTeardownBlock { try self.harness.client.armFault(FaketandemFaultSpec(.radioOn)) }
        let reconciliationBefore = try XCTUnwrap(try harness.sync(driver))
        let batchesBefore = driver.delegate.pumpEventBatches.count

        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        // So the reconnect's boundary is strictly newer than the sync's.
        try XCTUnwrap(driver.clock as? ManualClock).advance(by: .minutes(1))
        return Outage(reconciliationBefore: reconciliationBefore, batchesBefore: batchesBefore, logStart: logStart)
    }

    private func assertSyncedOnItsOwn(
        _ driver: FaketandemHarness.Driver,
        after outage: Outage,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try IntegrationWait.until("the driver to sync on its own", timeout: timeout) {
            try driver.delegate.pumpEventBatches.count > outage.batchesBefore
                && self.harness.requestsSeen(since: outage.logStart).contains { $0.message == "CurrentBasalStatusRequest" }
        }
        let boundary = try XCTUnwrap(driver.manager.state.lastReconciliation, file: file, line: line)
        XCTAssertGreaterThan(boundary, outage.reconciliationBefore, file: file, line: line)
        XCTAssertEqual(driver.delegate.pumpEventBatches.last?.lastReconciliation, boundary, file: file, line: line)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)", file: file, line: line)
    }

    /// A command job queued before the pump was deleted, such as a backfill tick's follow-up, must
    /// not bring the session back and hold the pump's one link.
    func testADeletedPumpIsNotReconnectedByALaterCommand() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        try deactivateDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let refused = expectation(description: "ensureConnected completes")
        var connectError: Error?
        driver.bluetooth.ensureConnected { error in
            connectError = error
            refused.fulfill()
        }
        wait(for: [refused], timeout: 30)

        XCTAssertNotNil(connectError)
        XCTAssertFalse(try harness.client.snapshot().connection.connected)
        XCTAssertEqual(try harness.requestLog(since: logStart).filter { $0.kind == "connection" }.count, 0)
    }

    /// Nothing else asks for a connection until the host's next command (jwoglom/tandemkit-stress#4).
    func testRelaunchedDriverReconnectsOnItsOwnWhenBluetoothWasOnBeforeItWasAttached() throws {
        let first = makeDriver()
        try harness.pair(first)
        let persisted = first.manager.state.rawValue
        try shutDownDriver()

        let relaunched = makeDriver(state: TandemPumpManagerState(rawValue: persisted), poweredOnBeforeAttach: true)

        try IntegrationWait.until("the relaunched driver to reconnect without a command", timeout: 30) {
            try relaunched.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
    }

    /// The host relaunches: a new manager built from the persisted rawState, with no pairing code
    /// re-entered, must reach the pump on its first command.
    func testRelaunchedDriverReconnectsFromPersistedStateOnTheNextCommand() throws {
        let first = makeDriver()
        try harness.pair(first)
        let persisted = first.manager.state.rawValue
        try shutDownDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let relaunched = makeDriver(state: TandemPumpManagerState(rawValue: persisted))
        XCTAssertNotNil(relaunched.manager.state.pumpState.derivedSecret, "rawState must round-trip the key")
        XCTAssertNotNil(relaunched.manager.state.pumpState.peripheralUuid)

        let lastSync = try harness.sync(relaunched)

        XCTAssertNotNil(lastSync)
        XCTAssertTrue(relaunched.manager.state.isConnected)
        XCTAssertTrue(try harness.client.snapshot().auth.authenticated)
        XCTAssertEqual(
            try authOpcodes(since: logStart),
            [Int(Jpake3SessionKeyRequest.props.opCode), Int(Jpake4KeyConfirmationRequest.props.opCode)]
        )
    }
}
