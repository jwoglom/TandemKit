import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitSetupCompleteViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitSetupCompleteViewModel

    private let basalError = PumpCommError.noResponse
    private let limitsError = PumpCommError.invalidPacket
    private var handedToHost = 0

    override func setUp() {
        super.setUp()
        handedToHost = 0
    }

    func testBasalFailureMessageNamesBasalRatesAndLeadsWithTheBasalError() {
        let message = ViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: basalError, deliveryLimits: limitsError)
        )

        XCTAssertTrue(message.contains("basal rates and delivery limits"))
        XCTAssertTrue(message.hasSuffix(basalError.localizedDescription))
    }

    func testBasalOnlyFailureDoesNotMentionLimits() {
        let message = ViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: basalError, deliveryLimits: nil)
        )

        XCTAssertTrue(message.contains("basal rates were not saved"))
        XCTAssertFalse(message.contains("delivery limits"))
    }

    func testLimitsOnlyFailureDoesNotClaimBasalRatesWereLost() {
        let message = ViewModel.message(
            for: OnboardingSettingsFailure(basalSchedule: nil, deliveryLimits: limitsError)
        )

        XCTAssertTrue(message.contains("delivery limits were not saved"))
        XCTAssertFalse(message.contains("basal rates"))
    }

    // MARK: - Control-IQ

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
    ) -> (ViewModel, StubPumpBluetooth) {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stub(ControlIQInfoV2Request.self, with: controlIQInfo(on: controlIQOn))
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 0))
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV3_4.value
        manager.state.featureFlags[.controlIQSupport] = controlIQSupport
        return (ViewModel(pumpManager: manager, loadsHistory: false, pumpIsSetUp: { [weak self] in self?.handedToHost += 1 }), bluetooth)
    }

    private func drainMainQueue() {
        for _ in 0 ..< 20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    func testAPumpRunningControlIQIsAskedAboutBeforeAnythingIsWritten() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)

        viewModel.start()
        drainMainQueue()

        XCTAssertTrue(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        XCTAssertFalse(bluetooth.didSend(ChangeTimeDateRequest.self), "the setup settings wait for the prompt")
        XCTAssertEqual(handedToHost, 0)
        XCTAssertFalse(viewModel.isFinished)
    }

    func testOKTurnsControlIQOffAndThenAppliesTheSetupSettings() throws {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)
        viewModel.start()
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

        viewModel.start()
        drainMainQueue()

        XCTAssertFalse(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testARefusedTurnOffHoldsSetupUntilATryAgainSucceeds() throws {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))
        viewModel.start()
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
        viewModel.start()
        drainMainQueue()
        bluetooth.stub(ControlIQInfoV2Request.self, with: controlIQInfo(on: false))

        viewModel.turnOffControlIQ()
        drainMainQueue()

        XCTAssertFalse(viewModel.isControlIQOffError)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testControlIQSupportStillAsksToTurnControlIQOff() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true, controlIQSupport: true)

        viewModel.start()
        drainMainQueue()

        XCTAssertTrue(viewModel.isPromptingControlIQOff)
        XCTAssertFalse(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testStartingTwiceAsksOnce() {
        let (viewModel, bluetooth) = pairedViewModel(controlIQOn: true)

        viewModel.start()
        viewModel.start()
        drainMainQueue()

        XCTAssertEqual(bluetooth.sent(ControlIQInfoV2Request.self).count, 1)
    }

    // MARK: - History load

    private func loadingViewModel() -> (ViewModel, StubPumpBluetooth) {
        let bluetooth = StubPumpBluetooth()
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = 123_456
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        return (ViewModel(pumpManager: manager, loadsHistory: true, pumpIsSetUp: { [weak self] in self?.handedToHost += 1 }), bluetooth)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testALoadThatFailsKeepsTheHostWaitingUntilTryAgainLoads() {
        let (viewModel, bluetooth) = loadingViewModel()

        viewModel.loadHistory()

        XCTAssertTrue(viewModel.isLoadingHistory)
        waitUntil { viewModel.isShowingLoadFailedAlert }
        XCTAssertEqual(viewModel.loadFailedMessage, SetupHistoryLoadError.historyUnreadable.localizedDescription)
        XCTAssertEqual(handedToHost, 0)
        XCTAssertFalse(viewModel.isFinished)

        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0))
        viewModel.isShowingLoadFailedAlert = false // as the alert does when Try Again is tapped
        viewModel.loadHistory()

        waitUntil { viewModel.isShowingLoadSummary }
        XCTAssertEqual(viewModel.progress, 1)
        XCTAssertFalse(viewModel.isLoadingHistory)
        XCTAssertEqual(viewModel.loadSummaryMessage, ViewModel.message(for: SetupHistoryLoadSummary(
            pumpBolusRecords: 0,
            pumpBasalRecords: 0,
            reportedBolusRecords: 0,
            reportedBasalRecords: 0
        )))
        XCTAssertEqual(handedToHost, 0, "the host gets the manager once the summary is dismissed")
        XCTAssertFalse(viewModel.isFinished)

        viewModel.loadSummaryAcknowledged()

        XCTAssertEqual(handedToHost, 1)
        XCTAssertTrue(viewModel.isFinished)
    }

    func testTheLoadSummaryCountsThePumpsRecordsThenWhatWasAdded() {
        let message = ViewModel.message(for: SetupHistoryLoadSummary(
            pumpBolusRecords: 12,
            pumpBasalRecords: 80,
            reportedBolusRecords: 4,
            reportedBasalRecords: 9
        ))
        let app = HostApp.current.appName

        XCTAssertEqual(
            message,
            "Successfully processed 12 pump bolus records and 80 pump basal records from your Tandem Mobi. "
                + "4 bolus records and 9 basal records were added to \(app).\n\n"
                + "To check what was imported, go to \(app)'s insulin treatments page."
        )
    }
}
