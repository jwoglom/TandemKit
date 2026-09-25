@testable import TandemKit
import XCTest

final class PairingIntegrationTests: FaketandemIntegrationTestCase {
    /// faketandem spawns pumpX2's jpake-server through goexpect, whose goterm `OpenPTY` issues the
    /// Linux-only `TIOCSPTLCK` ioctl; on macOS `/dev/ptmx` answers ENOTTY ("inappropriate ioctl for
    /// device"), the handler fails and `Jpake1aRequest` is never answered. Strict: once the
    /// emulator is fixed this reports "expected failure did not occur" and the wrapper goes.
    private static let freshPairingGap =
        "faketandem: pumpX2 jpake-server cannot be spawned on macOS (goterm OpenPTY TIOCSPTLCK); Jpake1aRequest goes unanswered"

    private var authRequests: [(opcode: Int, message: String, characteristic: String)] {
        get throws {
            try harness.requestsSeen().filter { $0.characteristic == "Authorization" }
        }
    }

    func testFreshJpakePairingAuthenticatesBothSides() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)

        let error = try harness.pair(driver, with: scan)

        XCTExpectFailure(Self.freshPairingGap) {
            XCTAssertNil(error, "pairPump failed: \(String(describing: error))")
        }
        guard error == nil else {
            // The exchange as the pump saw it: round 1a arrived and nothing went back.
            let seen = try authRequests
            XCTAssertEqual(seen.map(\.message), ["Jpake1aRequest"], "\(seen)")
            let responses = try harness.requestLog().filter { $0.isResponse && $0.characteristic == "Authorization" }
            XCTAssertTrue(responses.isEmpty, "the pump answered after all: \(responses)")
            XCTAssertFalse(try harness.client.snapshot().auth.authenticated)
            return
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
        XCTExpectFailure(Self.freshPairingGap) {
            let responses = try? harness.requestLog().filter { $0.isResponse && $0.characteristic == "Authorization" }
            XCTAssertFalse(
                responses?.isEmpty ?? true,
                "the refusal must come from the pump having run JPAKE, not from silence"
            )
        }
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
