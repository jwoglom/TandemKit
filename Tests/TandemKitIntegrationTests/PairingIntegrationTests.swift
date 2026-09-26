@testable import TandemKit
import XCTest

final class PairingIntegrationTests: FaketandemIntegrationTestCase {
    private var authRequests: [(opcode: Int, message: String, characteristic: String)] {
        get throws {
            try harness.requestsSeen().filter { $0.characteristic == "Authorization" }
        }
    }

    func testFreshJpakePairingAuthenticatesBothSides() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)

        let error = try harness.pair(driver, with: scan)

        if let error {
            // The exchange as the pump saw it, so "the pump never answered" and "the driver
            // ignored the answer" stay distinguishable.
            let seen = try authRequests
            let answered = try harness.requestLog().filter { $0.isResponse && $0.characteristic == "Authorization" }
            return XCTFail(
                "pairPump failed: \(error); pump saw \(seen.map(\.message)) and answered \(answered.map { $0.message ?? "?" })"
            )
        }

        let pumpState = driver.manager.state.pumpState
        XCTAssertNotNil(pumpState.derivedSecret, "JPAKE must leave the driver holding the derived key")
        XCTAssertNotNil(pumpState.serverNonce)
        XCTAssertEqual(pumpState.pincode, FaketandemHarness.pairingCode)
        XCTAssertEqual(pumpState.peripheralUuid, scan.bleIdentifier)
        XCTAssertNotNil(pumpState.timeSinceReset, "setup ends with a signed TimeSinceResetRequest")
        XCTAssertTrue(driver.manager.state.isConnected)

        let snapshot = try harness.client.snapshot()
        XCTAssertTrue(snapshot.auth.authenticated, "the pump must consider this session authenticated")
        XCTAssertTrue(snapshot.auth.longTermKeyPresent, "a completed pairing caches the long-term key")
        XCTAssertEqual(
            try harness.control.pairingStatus().longTermKey,
            pumpState.derivedSecret,
            "both sides must cache the same long-term key or quick reconnect can never succeed"
        )
        XCTAssertEqual(
            try authRequests.map(\.opcode),
            [
                Int(Jpake1aRequest.props.opCode),
                Int(Jpake1bRequest.props.opCode),
                Int(Jpake2Request.props.opCode),
                Int(Jpake3SessionKeyRequest.props.opCode),
                Int(Jpake4KeyConfirmationRequest.props.opCode),
            ],
            "a fresh pairing runs every JPAKE round in order"
        )
    }

    func testPairingWithTheWrongCodeIsRefused() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)

        let error = try harness.pair(driver, with: scan, code: "654321")

        XCTAssertNotNil(error, "a wrong pairing code must fail pairPump")
        XCTAssertNil(driver.manager.state.pumpState.derivedSecret)
        XCTAssertFalse(driver.manager.state.isConnected)
        let snapshot = try harness.client.snapshot()
        XCTAssertFalse(snapshot.auth.authenticated)
        XCTAssertFalse(snapshot.auth.longTermKeyPresent, "a failed pairing must not cache a key")
        let responses = try harness.requestLog().filter { $0.isResponse && $0.characteristic == "Authorization" }
        XCTAssertFalse(
            responses.isEmpty,
            "the refusal must come from the pump having run JPAKE, not from silence"
        )
    }

    /// The post-pairing state staged directly (the same key on both sides), then a connect that
    /// authenticates through rounds 3/4 only. Every other flow test starts this way.
    func testSeededLongTermKeyAuthenticatesThroughQuickReconnect() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)
        let key = try harness.seedLongTermKey(driver, peripheralId: scan.peripheral.identifier)

        let error = try harness.pair(driver, with: scan)

        XCTAssertNil(error, "pairPump failed: \(String(describing: error))")
        XCTAssertTrue(driver.manager.state.isConnected)
        XCTAssertEqual(driver.manager.state.pumpState.derivedSecret, key, "quick reconnect keeps the key it was given")
        XCTAssertNotNil(driver.manager.state.pumpState.serverNonce, "round 3 hands out a fresh server nonce")
        XCTAssertNotNil(driver.manager.state.pumpState.timeSinceReset)

        let snapshot = try harness.client.snapshot()
        XCTAssertTrue(snapshot.auth.authenticated)
        XCTAssertTrue(snapshot.connection.connected)
        XCTAssertEqual(try harness.control.pairingStatus().longTermKey, key)
        XCTAssertEqual(
            try authRequests.map(\.opcode),
            [Int(Jpake3SessionKeyRequest.props.opCode), Int(Jpake4KeyConfirmationRequest.props.opCode)],
            "a cached key skips rounds 1a/1b/2"
        )
    }
}
