import CoreBluetooth
@testable import TandemKit
import XCTest

// CBPeripheral cannot be constructed on Apple platforms, and the virtual pump's needs a central.
#if os(Linux) && !TANDEMKIT_VIRTUAL_PUMP

/// https://github.com/jwoglom/TandemKit/issues/399
@available(macOS 13.0, iOS 14.0, *) final class PairingFailureTests: XCTestCase {
    private let code = "123456"
    private let peripheral = CBPeripheral(identifier: UUID())
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    func testARefusedCodeIsReportedAndNotKept() {
        bluetooth.connectError = PumpCommError.pairingCodeRejected
        var reported: Error?

        manager.pairPump(code: code, peripheral: peripheral) { reported = $0 }

        guard let reported, case PumpCommError.pairingCodeRejected = reported else {
            return XCTFail("expected pairingCodeRejected, got \(String(describing: reported))")
        }
        XCTAssertNil(manager.state.pumpState.pincode)
    }

    func testAnAcceptedCodeIsKept() {
        var reported: Error?

        manager.pairPump(code: code, peripheral: peripheral) { reported = $0 }

        XCTAssertNil(reported)
        XCTAssertEqual(manager.state.pumpState.pincode, code)
    }

    func testAnEarlierAttemptsFailureDoesNotForgetALaterAttemptsCode() {
        bluetooth.holdsConnectCompletion = true
        manager.pairPump(code: code, peripheral: peripheral) { _ in }
        let firstAttempt = bluetooth.heldConnectCompletion
        manager.pairPump(code: "654321", peripheral: peripheral) { _ in }

        firstAttempt?(PumpCommError.noResponse)

        XCTAssertEqual(manager.state.pumpState.pincode, "654321")
    }

    /// A pump that has never paired has no key to authenticate with, so a command job or an
    /// automatic reconnect that connected would start a pairing of its own with the stored code.
    func testAnUnpairedPumpIsNotConnectedByAnythingButPairPump() {
        let realBluetooth = TandemBluetoothManager()
        let unpaired = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: realBluetooth)
        realBluetooth.manager?.state = .poweredOn
        // The Linux central never completes a connect, and the command below waits behind the attempt.
        realBluetooth.pairingTimeout = .milliseconds(500)
        realBluetooth.connect(peripheral) { _ in }

        let started = Date()
        let finished = expectation(description: "ensureConnected completes")
        var result: Error?
        realBluetooth.ensureConnected { error in
            result = error
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)

        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "a connect attempt waits out its 30 s timeout")
        guard let result, case PumpCommError.pumpNotConnected = result else {
            return XCTFail("expected pumpNotConnected, got \(String(describing: result))")
        }
        withExtendedLifetime(unpaired) {}
    }
}

#endif

/// What the onboarding alert shows for each way pairing can end.
@available(macOS 13.0, iOS 14.0, *) final class PairingFailureMessageTests: XCTestCase {
    func testARefusedCodeNamesThePairingCodeAndThePin() throws {
        let error = PumpCommError.pairingCodeRejected

        XCTAssertTrue(error.localizedDescription.contains("pairing code"))
        XCTAssertTrue(try XCTUnwrap(error.recoverySuggestion).contains("PIN"))
    }

    func testARefusedCodeIsNotDescribedAsAMissingResponse() {
        XCTAssertNotEqual(
            PumpCommError.pairingCodeRejected.localizedDescription,
            PumpCommError.noResponse.localizedDescription
        )
    }
}
