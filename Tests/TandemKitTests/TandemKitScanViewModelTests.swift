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
