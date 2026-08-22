import LoopKit
@testable import TandemKit
import XCTest

/// Covers the pre-flight checks `enactBolus` runs before it touches the pump. The pump enforces
/// its own max bolus limit too; these guards exist so an out-of-range request fails fast with a
/// specific error rather than as a generic mid-handshake rejection.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerValidationTests: XCTestCase {
    private func makeManager(settings: TandemPumpManagerSettings) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.settings = settings
        return TandemPumpManager(state: state)
    }

    func testBolusExceedingMaxBolusIsRejected() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertEqual(
            manager.validateBolusRequest(units: 6.0),
            .maximumBolusExceeded(requested: 6.0, maximum: 5.0)
        )
    }

    func testBolusAtMaxBolusIsAllowed() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertNil(manager.validateBolusRequest(units: 5.0))
    }

    func testNonPositiveBolusIsRejected() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertEqual(manager.validateBolusRequest(units: 0), .invalidBolusAmount(requested: 0))
        XCTAssertEqual(manager.validateBolusRequest(units: -1.0), .invalidBolusAmount(requested: -1.0))
    }

    /// Until the host app syncs delivery limits there is no maximum to check against, so only the
    /// positive-amount guard applies — the pump remains the backstop.
    func testUnsyncedDeliveryLimitsOnlyEnforcePositiveAmount() {
        let manager = makeManager(settings: TandemPumpManagerSettings())

        XCTAssertNil(manager.validateBolusRequest(units: 25.0))
        XCTAssertEqual(manager.validateBolusRequest(units: 0), .invalidBolusAmount(requested: 0))
    }

    func testEnactBolusSurfacesValidationErrorAsDeviceState() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        let expectation = expectation(description: "Bolus completion")
        manager.enactBolus(units: 6.0, activationType: .manualNoRecommendation) { error in
            guard case let .deviceState(underlyingError?) = error,
                  let validationError = underlyingError as? TandemPumpManagerValidationError
            else {
                XCTFail("Expected deviceState validation error, received: \(String(describing: error))")
                expectation.fulfill()
                return
            }

            XCTAssertEqual(validationError, .maximumBolusExceeded(requested: 6.0, maximum: 5.0))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Control-IQ

    private func makeControlIQManager() -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.settings = TandemPumpManagerSettings(maxBolus: 5.0)
        state.useControlIQ = true
        return TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())
    }

    private func validationError(from error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .deviceState(underlyingError?) = error else { return nil }
        return underlyingError as? TandemPumpManagerValidationError
    }

    func testAutomaticBolusIsBlockedWhileControlIQIsActive() {
        let manager = makeControlIQManager()

        let expectation = expectation(description: "Bolus completion")
        var error: PumpManagerError?
        manager.enactBolus(units: 1.0, activationType: .automatic) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(validationError(from: error), .controlIQModeActive)
    }

    func testTempBasalIsBlockedWhileControlIQIsActive() {
        let manager = makeControlIQManager()

        let expectation = expectation(description: "Temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(unitsPerHour: 1.0, for: .minutes(30)) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(validationError(from: error), .controlIQModeActive)
    }

    /// The host app is the only thing that renders this, and it wraps it in its own generic
    /// wording -- Trio prefixes pump errors with "Trio could not communicate with the pump". The
    /// text therefore has to name Control-IQ and say that dosing is paused all by itself, or the
    /// user is left reading what looks like a Bluetooth problem.
    func testControlIQBlockExplainsItselfWithoutHostContext() throws {
        let message = try XCTUnwrap(TandemPumpManagerValidationError.controlIQModeActive.errorDescription)

        XCTAssertTrue(message.localizedCaseInsensitiveContains("control-iq"), "Got: \(message)")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("paused"), "Got: \(message)")

        let recovery = try XCTUnwrap(TandemPumpManagerValidationError.controlIQModeActive.recoverySuggestion)
        XCTAssertTrue(recovery.localizedCaseInsensitiveContains("control-iq"), "Got: \(recovery)")
    }
}
