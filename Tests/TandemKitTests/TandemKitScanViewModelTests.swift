import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitScanViewModelTests: XCTestCase {
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

    private func scanViewModel() -> TandemKitScanViewModel {
        let viewModel = TandemKitScanViewModel(nextStep: {})
        viewModel.codeStepSettleInterval = 0.05
        return viewModel
    }

    private func waitPastTheSettleInterval() {
        let settled = expectation(description: "settle interval passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    func testThePumpPickedUpIsFollowedThoughAnotherWasHeardFirst() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("emulator", name: "Tandem Mobi 123", step: 0x10)
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x11)

        XCTAssertEqual(viewModel.currentPhase, .doubleTap)
        XCTAssertEqual(viewModel.connectingTo, "Tandem Mobi 994")

        viewModel.pumpHeard("emulator", name: "Tandem Mobi 123", step: 0x10)
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x12)
        viewModel.multiplePumpsDismissed()
        waitPastTheSettleInterval()

        XCTAssertTrue(viewModel.isPromptingPincode)
        XCTAssertEqual(viewModel.connectingTo, "Tandem Mobi 994")
    }

    func testAPumpAtTheCodeStepWhileThePlaceOnPadStepShowsGoesStraightToTheCode() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x10)
        XCTAssertEqual(viewModel.currentPhase, .mobiOnPad)

        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x12)
        waitPastTheSettleInterval()

        XCTAssertTrue(viewModel.isPromptingPincode)
    }

    func testTwoPumpsAtTheCodeStepPairNeitherUntilOneLeavesIt() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x12)
        viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: 0x12)
        viewModel.multiplePumpsDismissed()
        waitPastTheSettleInterval()

        XCTAssertFalse(viewModel.isPromptingPincode)
        XCTAssertEqual(viewModel.currentPhase, .doubleTap)

        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x10)
        waitPastTheSettleInterval()

        XCTAssertTrue(viewModel.isPromptingPincode)
        XCTAssertEqual(viewModel.connectingTo, "Tandem Mobi 994")
    }

    func testAPumpThatGoesQuietKeepsTheStepItLastAdvertised() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x12)
        viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: 0x12)
        viewModel.multiplePumpsDismissed()

        for _ in 0 ..< 5 { viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: 0x12) }
        waitPastTheSettleInterval()

        XCTAssertFalse(viewModel.isPromptingPincode)
    }

    func testAnAdvertWithNoPairingStepLeavesTheLastOne() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x11)

        viewModel.pumpHeard("mobi", name: "", step: nil)

        XCTAssertEqual(viewModel.currentPhase, .doubleTap)
        XCTAssertEqual(viewModel.connectingTo, "Tandem Mobi 994")
    }

    func testASecondPumpRaisesTheMultiplePumpsNoticeNamingBoth() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x10)
        XCTAssertFalse(viewModel.isMultiplePumpsFound)

        viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: nil)

        XCTAssertTrue(viewModel.isMultiplePumpsFound)
        XCTAssertTrue(viewModel.multiplePumpsMessage.contains("Tandem Mobi 123"))
        XCTAssertTrue(viewModel.multiplePumpsMessage.contains("Tandem Mobi 994"))
    }

    func testAPumpHeardWhileTheNoticeShowsJoinsItAndOnlyANewPumpRaisesItAgain() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x10)
        viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: 0x10)

        viewModel.pumpHeard("c", name: "Tandem Mobi 555", step: 0x10)
        XCTAssertTrue(viewModel.multiplePumpsMessage.contains("Tandem Mobi 555"))
        viewModel.multiplePumpsDismissed()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x11)
        XCTAssertFalse(viewModel.isMultiplePumpsFound)

        viewModel.pumpHeard("d", name: "Tandem Mobi 777", step: 0x10)
        XCTAssertTrue(viewModel.isMultiplePumpsFound)
    }

    func testTheCodePromptWaitsForTheMultiplePumpsNoticeToBeDismissed() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("a", name: "Tandem Mobi 123", step: 0x10)
        viewModel.pumpHeard("b", name: "Tandem Mobi 994", step: 0x12)
        waitPastTheSettleInterval()

        XCTAssertTrue(viewModel.isMultiplePumpsFound)
        XCTAssertFalse(viewModel.isPromptingPincode)

        viewModel.multiplePumpsDismissed()

        XCTAssertTrue(viewModel.isPromptingPincode)
    }

    func testACancelledCodePromptWaitsForThePumpToAdvertiseTheCodeStepAgain() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x12)
        waitPastTheSettleInterval()
        XCTAssertTrue(viewModel.isPromptingPincode)

        viewModel.cancelPinPrompt()
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: nil)
        waitPastTheSettleInterval()
        XCTAssertFalse(viewModel.isPromptingPincode)

        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x12)
        waitPastTheSettleInterval()
        XCTAssertTrue(viewModel.isPromptingPincode)
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

    func testThePairingCodeKeepsOnlyItsFirstSixDigits() {
        let viewModel = TandemKitScanViewModel(nextStep: {})

        viewModel.devicePinCode = "12 3-4a５5678"

        XCTAssertEqual(viewModel.devicePinCode, "123456")
        XCTAssertTrue(viewModel.isPinCodeComplete)
    }

    func testThePinPromptNamesThePumpItPairs() {
        let viewModel = scanViewModel()
        viewModel.pumpHeard("mobi", name: "Tandem Mobi 994", step: 0x12)
        waitPastTheSettleInterval()

        XCTAssertTrue(viewModel.isPromptingPincode)
        XCTAssertEqual(viewModel.pinPromptHeading, "Enter the PIN for Tandem Mobi 994:")
    }

    func testAPairingCodeShortOfSixDigitsIsNotSent() {
        let viewModel = TandemKitScanViewModel(nextStep: {})
        viewModel.isPromptingPincode = true
        viewModel.devicePinCode = "12345"

        viewModel.processPinPrompt()

        XCTAssertTrue(viewModel.isPromptingPincode)
        XCTAssertNotEqual(viewModel.currentPhase, .pairing)
        XCTAssertNotNil(viewModel.pinCodePromptError)

        viewModel.devicePinCode = "123456"
        XCTAssertNil(viewModel.pinCodePromptError)
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

    func testASuccessfulPairingGoesOnWithoutWritingToThePump() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        var steps = 0
        let viewModel = TandemKitScanViewModel(manager, nextStep: { steps += 1 })

        viewModel.onPairSuccess()
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(steps, 1)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
