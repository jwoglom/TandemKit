import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitScanViewModelTests: XCTestCase {
    private let basalError = PumpCommError.noResponse
    private let limitsError = PumpCommError.invalidPacket

    private func connectedElsewhereViewModel(_ names: [String]) -> TandemKitScanViewModel {
        let bluetooth = StubPumpBluetooth()
        bluetooth.connectedNames = names
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        return TandemKitScanViewModel(manager, nextStep: {})
    }

    func testAPumpConnectedToThePhoneRaisesTheForgetPromptNamingIt() {
        let viewModel = connectedElsewhereViewModel(["Tandem Mobi 1234"])

        viewModel.checkForConnectedPump()

        XCTAssertTrue(viewModel.isConnectedElsewhere)
        XCTAssertTrue(viewModel.connectedElsewhereMessage.contains("Tandem Mobi 1234"))
    }

    func testNoConnectedPumpRaisesNoPrompt() {
        let viewModel = connectedElsewhereViewModel([])

        viewModel.checkForConnectedPump()

        XCTAssertFalse(viewModel.isConnectedElsewhere)
    }

    func testDismissingThePromptSilencesItUntilTheIntervalPasses() {
        let viewModel = connectedElsewhereViewModel(["Tandem Mobi 1234"])
        viewModel.checkForConnectedPump()

        viewModel.connectedElsewhereDismissed()
        viewModel.checkForConnectedPump()

        XCTAssertFalse(viewModel.isConnectedElsewhere)
    }

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

    func testThePairingStepIsTheLastByteOfThePumpsManufacturerData() {
        let manufacturerData = Data([0x9D, 0x05, 0x00, 0x01, 0x11])
        XCTAssertEqual(
            TandemKitScanViewModel.advertisedPairingStep(
                name: "Tandem Mobi 123",
                advertisementData: [CBAdvertisementDataManufacturerDataKey: manufacturerData]
            ),
            0x11
        )
        XCTAssertNil(TandemKitScanViewModel.advertisedPairingStep(name: "Tandem Mobi 123", advertisementData: [:]))
        XCTAssertNil(TandemKitScanViewModel.advertisedPairingStep(name: "Tandem Mobi 123", advertisementData: nil))
    }

    func testAPumpNamedAsASimulatorIsReadyForItsCode() {
        XCTAssertEqual(
            TandemKitScanViewModel.advertisedPairingStep(name: "Tandem Mobi Simulator 123", advertisementData: nil),
            0x12
        )
        // CoreBluetooth names a Mac it has connected to by the Mac's own name; the advertisement still says.
        XCTAssertEqual(
            TandemKitScanViewModel.advertisedPairingStep(
                name: "Someone's MacBook",
                advertisementData: [CBAdvertisementDataLocalNameKey: "Tandem Mobi Simulator 123"]
            ),
            0x12
        )
        XCTAssertTrue(TandemPumpScan.isSimulatorName("SIM Tandem Mobi 123"))
        XCTAssertTrue(TandemPumpScan.isSimulatorName("Tandem Mobi SIM"))
        XCTAssertTrue(TandemPumpScan.isSimulatorName("tslim X2 simulator"))
        XCTAssertFalse(TandemPumpScan.isSimulatorName("Tandem Mobi 123"))
        XCTAssertFalse(TandemPumpScan.isSimulatorName("tslim X2 ***123"))
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

    // MARK: - Control-IQ at setup

    private func controlIQInfo(on: Bool) -> ControlIQInfoV2Response {
        ControlIQInfoV2Response(
            closedLoopEnabled: on,
            weight: 150,
            weightUnit: ControlIQInfoAbstractResponse.WeightUnit.pounds.rawValue,
            totalDailyInsulin: 40,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )
    }

    private func pairedViewModel(
        controlIQOn: Bool,
        controlIQSupport: Bool = false
    ) -> (TandemKitScanViewModel, StubPumpBluetooth) {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stub(ControlIQInfoV2Request.self, with: controlIQInfo(on: controlIQOn))
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 0))
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV3_4.value
        manager.state.featureFlags[.controlIQSupport] = controlIQSupport
        return (TandemKitScanViewModel(manager, nextStep: {}), bluetooth)
    }

    private func drainMainQueue() {
        for _ in 0 ..< 20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    func testAPumpRunningControlIQIsAskedAboutBeforeAnythingIsWritten() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)

        viewModel.onPairSuccess()
        drainMainQueue()

        XCTAssertTrue(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        XCTAssertFalse(bluetooth.didSend(ChangeTimeDateRequest.self), "the setup settings wait for the prompt")
    }

    func testOKTurnsControlIQOffAndThenAppliesTheSetupSettings() throws {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)
        viewModel.onPairSuccess()
        drainMainQueue()

        viewModel.turnOffControlIQ()
        drainMainQueue()

        let request = try XCTUnwrap(bluetooth.sent(ChangeControlIQSettingsRequest.self).first)
        XCTAssertFalse(request.enabled)
        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        let turnedOff = try XCTUnwrap(order.firstIndex(of: "ChangeControlIQSettingsRequest"))
        let clockSet = try XCTUnwrap(order.firstIndex(of: "ChangeTimeDateRequest"))
        XCTAssertLessThan(turnedOff, clockSet)
        XCTAssertFalse(viewModel.isControlIQOffError)
    }

    func testAPumpWithControlIQOffGoesStraightToTheSetupSettings() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: false)

        viewModel.onPairSuccess()
        drainMainQueue()

        XCTAssertFalse(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testARefusedTurnOffHoldsSetupUntilATryAgainSucceeds() throws {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))
        viewModel.onPairSuccess()
        drainMainQueue()

        viewModel.turnOffControlIQ()
        drainMainQueue()

        XCTAssertTrue(viewModel.isControlIQOffError)
        let message = try XCTUnwrap(viewModel.controlIQOffErrorMessage)
        XCTAssertTrue(message.hasSuffix(ControlIQConfigurationError.pumpRejected(status: 1).localizedDescription))
        XCTAssertFalse(bluetooth.didSend(ChangeTimeDateRequest.self))

        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 0))
        viewModel.isControlIQOffError = false // as the alert does when Try Again is tapped
        viewModel.turnOffControlIQ()
        drainMainQueue()

        XCTAssertFalse(viewModel.isControlIQOffError)
        XCTAssertEqual(bluetooth.sent(ChangeControlIQSettingsRequest.self).count, 2)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testARefusedTurnOffOfAPumpThatReadsOffGoesOnWithSetup() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))
        viewModel.onPairSuccess()
        drainMainQueue()
        bluetooth.stub(ControlIQInfoV2Request.self, with: controlIQInfo(on: false))

        viewModel.turnOffControlIQ()
        drainMainQueue()

        XCTAssertFalse(viewModel.isControlIQOffError)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testControlIQSupportStillAsksToTurnControlIQOff() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true, controlIQSupport: true)

        viewModel.onPairSuccess()
        drainMainQueue()

        XCTAssertTrue(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeTimeDateRequest.self))
    }
}
