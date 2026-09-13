@testable import TandemKit
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
