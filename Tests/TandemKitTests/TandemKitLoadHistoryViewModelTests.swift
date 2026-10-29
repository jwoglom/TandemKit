import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitLoadHistoryViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitLoadHistoryViewModel

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var choices: [Bool] = []

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = 123_456
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        choices = []
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeViewModel(_ reading: SetupDeliveryReading = SetupDeliveryReading()) -> ViewModel {
        ViewModel(reading: reading, now: { [now] in now }, done: { [weak self] in self?.choices.append($0) })
    }

    func testTheScreenOpensOnTheChoiceAndNamesTheApp() {
        let viewModel = makeViewModel(SetupDeliveryReading(insulinOnBoard: 1))

        XCTAssertEqual(
            viewModel.introduction,
            "The Tandem Mobi you just connected reports the following insulin delivery information:"
        )
        XCTAssertEqual(
            viewModel.question,
            "Would you like to load this insulin delivery information into \(viewModel.appName) so it is included in your IOB?"
        )
        XCTAssertEqual(viewModel.loadButtonTitle, "Load Pump History into \(viewModel.appName)")
    }

    func testTheReadingsAreTheInsulinOnBoardTheLastBolusAndTheBasalRate() throws {
        let viewModel = makeViewModel(SetupDeliveryReading(
            insulinOnBoard: 2.3,
            lastBolus: .delivered(at: now.addingTimeInterval(-80 * 60)),
            currentBasalRate: 0.85
        ))

        XCTAssertEqual(viewModel.readings.count, 3)
        XCTAssertEqual(viewModel.readings[0], ViewModel.Reading(label: "Insulin on Board:", value: "2.30 units"))
        XCTAssertEqual(viewModel.readings[1].label, "Last bolus delivery:")
        XCTAssertTrue(viewModel.readings[1].value.hasSuffix(" (1 hour 20 minutes ago)"), viewModel.readings[1].value)
        XCTAssertEqual(viewModel.readings[2], ViewModel.Reading(label: "Current basal rate:", value: "0.85 u/hr"))
    }

    func testASuspendedPumpSaysSoInPlaceOfItsBasalRate() {
        let viewModel = makeViewModel(SetupDeliveryReading(insulinOnBoard: 0, lastBolus: .none, isSuspended: true))

        XCTAssertEqual(viewModel.readings, [
            ViewModel.Reading(label: "Insulin on Board:", value: "0.00 units"),
            ViewModel.Reading(label: nil, value: "Insulin delivery currently suspended")
        ])
    }

    func testAReadingThePumpDidNotAnswerIsLeftOut() {
        XCTAssertEqual(
            makeViewModel(SetupDeliveryReading(insulinOnBoard: 1)).readings,
            [ViewModel.Reading(label: "Insulin on Board:", value: "1.00 units")]
        )
    }

    func testAPumpThatReportedNothingIsStillAskedAbout() {
        let viewModel = makeViewModel(SetupDeliveryReading(lastBolus: .none))

        XCTAssertEqual(viewModel.readings, [])
        XCTAssertEqual(
            viewModel.question,
            "Would you like to load the pump's insulin delivery history into \(viewModel.appName) so it is included in your IOB?"
        )
    }

    func testNotLoadingSaysTheAppWillNotCountThePumpsInsulinBeforeSetupGoesOn() throws {
        let viewModel = makeViewModel()

        viewModel.doNotLoad()

        XCTAssertTrue(viewModel.isShowingNotLoadedAlert)
        let first = try XCTUnwrap(viewModel.notLoadedMessage.first)
        XCTAssertTrue(first.isUppercase)
        XCTAssertTrue(viewModel.notLoadedMessage.hasSuffix(" will not count insulin this pump delivered before you connected it."))
        XCTAssertEqual(choices, [])

        viewModel.notLoadedAcknowledged()

        XCTAssertEqual(choices, [false])
    }

    func testNotLoadingLeavesTheLedgersWhereTheyWere() {
        let trackingSince = manager.state.bolusReportLedger.trackingSince
        let viewModel = makeViewModel()

        viewModel.doNotLoad()
        viewModel.notLoadedAcknowledged()

        XCTAssertEqual(manager.state.bolusReportLedger.trackingSince, trackingSince)
    }

    func testLoadingIsChosenHereAndRunsAfterTheSetupSync() {
        let trackingSince = manager.state.bolusReportLedger.trackingSince

        makeViewModel().load()

        XCTAssertEqual(choices, [true])
        XCTAssertEqual(manager.state.bolusReportLedger.trackingSince, trackingSince)
    }
}
