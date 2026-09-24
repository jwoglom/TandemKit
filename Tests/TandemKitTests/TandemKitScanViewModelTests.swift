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
}
