import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitScanViewModelTests: XCTestCase {
    private let basalError = PumpCommError.noResponse
    private let limitsError = PumpCommError.invalidPacket

    func testBasalFailureMessageNamesBasalRatesAndLeadsWithTheBasalError() {
        let message = TandemKitScanViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: basalError, deliveryLimits: limitsError)
        )

        XCTAssertTrue(message.contains("basal rates and delivery limits"))
        XCTAssertTrue(message.hasSuffix(basalError.localizedDescription))
    }

    func testBasalOnlyFailureDoesNotMentionLimits() {
        let message = TandemKitScanViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: basalError, deliveryLimits: nil)
        )

        XCTAssertTrue(message.contains("basal rates were not saved"))
        XCTAssertFalse(message.contains("delivery limits"))
    }

    func testLimitsOnlyFailureDoesNotClaimBasalRatesWereLost() {
        let message = TandemKitScanViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: nil, deliveryLimits: limitsError)
        )

        XCTAssertTrue(message.contains("delivery limits were not saved"))
        XCTAssertFalse(message.contains("basal rates"))
    }

    func testARefusedCodeTitleSaysSoAndAnyOtherFailureIsGeneric() {
        XCTAssertEqual(
            TandemKitScanViewModel.pairingFailureTitle(for: PumpCommError.pairingCodeRejected),
            "Pairing Code Not Accepted"
        )
        XCTAssertEqual(TandemKitScanViewModel.pairingFailureTitle(for: PumpCommError.noResponse), "Pairing Failed")
    }

    func testPairingFailureMessageFollowsTheErrorWithItsRecoverySuggestion() throws {
        let error = PumpCommError.pairingCodeRejected

        let message = TandemKitScanViewModel.pairingFailureMessage(for: error)

        XCTAssertTrue(message.hasPrefix(error.localizedDescription))
        XCTAssertTrue(message.hasSuffix(try XCTUnwrap(error.recoverySuggestion)))
    }

    func testPairingFailureMessageIsTheDescriptionWhenThereIsNoSuggestion() {
        let error = PumpCommError.invalidPacket

        XCTAssertNil(error.recoverySuggestion)
        XCTAssertEqual(TandemKitScanViewModel.pairingFailureMessage(for: error), error.localizedDescription)
    }

    /// The pairing step has no way out of its own: nothing but this ends it.
    func testAFailedPairingLeavesThePairingStepWithTheErrorShown() {
        let viewModel = TandemKitScanViewModel(nextStep: {})
        viewModel.currentPhase = .pairing
        viewModel.devicePinCode = "123456"

        viewModel.onPairFailure(error: PumpCommError.pairingCodeRejected)
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertNotEqual(viewModel.currentPhase, .pairing)
        XCTAssertTrue(viewModel.isConnectionError)
        XCTAssertEqual(viewModel.connectionErrorTitle, "Pairing Code Not Accepted")
        XCTAssertEqual(viewModel.devicePinCode, "")
    }
}
