@testable import TandemKit
import XCTest

final class PairingIntegrationTests: FaketandemIntegrationTestCase {
    func testFreshJpakePairingAuthenticatesBothSides() throws {
        let driver = makeDriver()
        let scan = try harness.discover(driver)

        let error = try harness.pair(driver, with: scan)

        XCTAssertNil(error, "pairPump failed: \(String(describing: error))")
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
        XCTAssertTrue(snapshot.connection.connected)

        let status = try harness.control.pairingStatus()
        XCTAssertTrue(status.authenticated)
        XCTAssertEqual(
            status.longTermKey,
            pumpState.derivedSecret,
            "both sides must cache the same long-term key or quick reconnect can never succeed"
        )

        let auth = try harness.requestsSeen().filter { $0.characteristic == "Authorization" }
        XCTAssertEqual(
            auth.map(\.opcode),
            [
                Int(Jpake1aRequest.props.opCode),
                Int(Jpake1bRequest.props.opCode),
                Int(Jpake2Request.props.opCode),
                Int(Jpake3SessionKeyRequest.props.opCode),
                Int(Jpake4KeyConfirmationRequest.props.opCode),
            ],
            "a fresh pairing runs every JPAKE round in order: \(auth)"
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
    }
}
