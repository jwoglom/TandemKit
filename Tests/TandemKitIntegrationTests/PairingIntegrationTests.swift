@testable import TandemKit
import XCTest

final class PairingIntegrationTests: FaketandemIntegrationTestCase {
    private var authRequests: [(opcode: Int, message: String, characteristic: String)] {
        get throws {
            try harness.requestsSeen().filter { $0.characteristic == "Authorization" }
        }
    }

    /// As when re-pairing a manager the host already holds, which keeps sending it commands.
    func testACommandQueuedWhilePairingRunsOnTheSessionPairingOpens() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)
        _ = try harness.seedLongTermKey(driver, peripheralId: scan.peripheral.identifier)
        let paired = ResultBox<Error?>()
        let command = ResultBox<Error?>()

        driver.manager.pairPump(code: FaketandemHarness.pairingCode, peripheral: scan.peripheral) { paired.set($0) }
        driver.bluetooth.ensureConnected { command.set($0) }

        XCTAssertNil(try paired.wait("pairPump completion", timeout: 60))
        XCTAssertNil(try command.wait("the queued command", timeout: 60))
        XCTAssertTrue(driver.manager.state.isConnected)
        XCTAssertEqual(
            try authRequests.map(\.opcode),
            [Int(Jpake3SessionKeyRequest.props.opCode), Int(Jpake4KeyConfirmationRequest.props.opCode)],
            "one session, authenticated once"
        )
    }

    /// testPairingWithTheWrongCodeIsRefused's dropped link, where Linux can run it: a first pairing needs SwiftECC.
    func testARePairingCutOffAtKeyConfirmationFailsAsAnUnansweredRound() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)
        _ = try harness.seedLongTermKey(driver, peripheralId: scan.peripheral.identifier)
        try harness.client.armFault(FaketandemFaultSpec(.disconnect, message: "Jpake4KeyConfirmationRequest"))

        let error = try harness.pair(driver, with: scan)

        guard let error, case PumpCommError.noResponse = error else {
            return XCTFail("pairPump must fail with the handshake's own error, got \(String(describing: error))")
        }
    }

    // Rounds 1-2 are EC-JPAKE, which is a trapping stub where SwiftECC does not build (Linux).
    #if canImport(SwiftECC)
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

        guard let error, case PumpCommError.pairingCodeRejected = error else {
            return XCTFail("a wrong code must fail pairPump as pairingCodeRejected, got \(String(describing: error))")
        }
        XCTAssertNil(driver.manager.state.pumpState.derivedSecret)
        XCTAssertNil(driver.manager.state.pumpState.pincode, "a refused code is not kept")
        XCTAssertFalse(driver.manager.state.isConnected)
        let snapshot = try harness.client.snapshot()
        XCTAssertFalse(snapshot.auth.authenticated)
        XCTAssertFalse(snapshot.auth.longTermKeyPresent, "a failed pairing must not cache a key")
        let responses = try harness.requestLog().filter { $0.isResponse && $0.characteristic == "Authorization" }
        XCTAssertFalse(
            responses.isEmpty,
            "the refusal must come from the pump having run JPAKE, not from silence"
        )

        // The pump drops the link on a refused code; the driver must not reconnect and run JPAKE again with it.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(
            try authRequests.filter { $0.opcode == Int(Jpake1aRequest.props.opCode) }.count,
            1,
            "a refused code must not be retried on its own"
        )
    }

    #endif

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
