import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Deleting the pump manager from Trio's pump settings and pairing a new one. The setup screen that
/// makes the new one cannot be driven, so Trio restores it from a seeded state at a relaunch
/// (`recreatePumpManager`), as every scenario's manager is.
final class TrioPumpDeletionTests: TrioTestCase {
    func testAConnectedPumpDeletedAndPairedAgainIsPairedAfresh() throws {
        try pairTrio()
        let firstKey = try harness.control.pairingStatus().longTermKey
        XCTAssertNotNil(firstKey)

        try deletePumpManager()

        try assertTheDeletedPumpManagerIsGone()
        try recreatePumpManager()
        try pairTrio(withCode: true)
        try assertTrioHoldsAPumpPairedAfresh(replacing: firstKey)
        XCTAssertEqual(try firstRoundsSeen(), 1, "the new manager pairs from the first round, not with the deleted manager's key")
    }

    /// The pump has met this phone before the second attempt: it ran the first exchange to key
    /// confirmation, refused the code and saw the link go. The virtual CoreBluetooth keeps no list of
    /// devices, so iOS's own memory of the pump has no counterpart here; what the second attempt
    /// meets is the pump's side and Trio's own data, which the re-creation keeps.
    func testAPumpThatRefusedTheCodeIsPairedAfreshOnceTheManagerIsDeletedAndMadeAgain() throws {
        XCTAssertThrowsError(try control.send(.init(command: .pair, code: "654321"))) { error in
            XCTAssertTrue(String(describing: error).contains("pairingCodeRejected"), "\(error)")
        }
        try IntegrationWait.until("the pump to see the refused attempt's link go", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }
        XCTAssertFalse(try harness.client.snapshot().auth.longTermKeyPresent, "a refused pairing leaves the pump no key")
        XCTAssertEqual(try control.send(.init(command: .status)).status?.onboarded, false, "Trio still holds the unpaired manager")

        try deletePumpManager()

        try assertTheDeletedPumpManagerIsGone()
        try recreatePumpManager()
        try pairTrio(withCode: true)
        try assertTrioHoldsAPumpPairedAfresh(replacing: nil)
        XCTAssertEqual(try firstRoundsSeen(), 2, "both attempts ran the exchange from its first round")
    }

    /// What can be seen of a deleted pump manager: no command reaches one, and the pump's link is
    /// down and stays down past the first reconnect retry a live manager would make (5 s).
    private func assertTheDeletedPumpManagerIsGone() throws {
        XCTAssertThrowsError(try control.send(.init(command: .status)), "no command reaches a deleted manager")
        try IntegrationWait.until("the pump to see the deleted manager's link go", timeout: 10) {
            try !self.harness.client.snapshot().connection.connected
        }
        try IntegrationWait.holds("the deleted manager leaving the pump alone", for: 7) {
            try !self.harness.client.snapshot().connection.connected
        }
        // Trio's DeviceDataManager writes its saved pump manager only when it takes one, so the deleted
        // one's file stays and a relaunch restores it. Strict: a Trio that removes it turns this into an
        // unexpected pass, and the wrapper comes out.
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        XCTExpectFailure("Trio keeps PumpManagerState.plist after the pump is deleted", options: options) {
            XCTAssertFalse(trio.hasSavedPumpManager(), "Trio keeps the deleted pump manager's saved state")
        }
    }

    /// The pump and Trio hold a key the pump derived in this pairing, not the deleted manager's.
    private func assertTrioHoldsAPumpPairedAfresh(replacing earlierKey: Data?) throws {
        let pump = try harness.client.snapshot()
        XCTAssertTrue(pump.connection.connected)
        XCTAssertTrue(pump.auth.authenticated)
        let key = try harness.control.pairingStatus().longTermKey
        XCTAssertNotNil(key, "a completed pairing leaves the pump its key")
        XCTAssertNotEqual(key, earlierKey, "a fresh pairing derives a new key")
        let saved = try IntegrationWait.value("Trio to have saved the paired manager", timeout: 30) { () -> TandemPumpManagerState? in
            guard let state = try self.trio.savedPumpManagerState(), state.onboarded else {
                return nil
            }
            return state
        }
        XCTAssertEqual(saved.pumpState.derivedSecret, key, "Trio holds the key the pump derived")
    }

    /// How many exchanges the pump saw start from `Jpake1aRequest` since the reset; a quick reconnect starts at round 3.
    private func firstRoundsSeen() throws -> Int {
        try harness.requestsSeen().filter { $0.characteristic == "Authorization" && $0.opcode == Int(Jpake1aRequest.props.opCode) }.count
    }
}
