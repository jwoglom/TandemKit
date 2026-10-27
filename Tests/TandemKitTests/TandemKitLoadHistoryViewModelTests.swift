import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitLoadHistoryViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitLoadHistoryViewModel

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var doneCount = 0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = 123_456
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        doneCount = 0
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func makeViewModel() -> ViewModel {
        ViewModel(pumpManager: manager, done: { [weak self] in self?.doneCount += 1 })
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testTheScreenOpensOnTheChoiceAndNamesTheApp() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.phase, .choosing)
        XCTAssertTrue(viewModel.explanation.contains("connected to \(viewModel.appName)."))
        XCTAssertTrue(viewModel.guidance.contains("so that \(viewModel.appName) knows your current IOB"))
        XCTAssertEqual(viewModel.loadButtonTitle, "Load Pump History into \(viewModel.appName)")
    }

    func testTheExplanationOpensWithACapital() throws {
        let first = try XCTUnwrap(makeViewModel().explanation.first)

        XCTAssertTrue(first.isUppercase)
    }

    func testNotLoadingWarnsOfZeroInsulinOnBoardBeforeSetupGoesOn() {
        let viewModel = makeViewModel()

        viewModel.doNotLoad()

        XCTAssertTrue(viewModel.isShowingNotLoadedAlert)
        XCTAssertTrue(viewModel.notLoadedMessage.contains("assumes you have 0 units of Insulin on Board"))
        XCTAssertEqual(doneCount, 0)

        viewModel.notLoadedAcknowledged()

        XCTAssertEqual(doneCount, 1)
    }

    func testNotLoadingLeavesTheLedgersWhereTheyWere() {
        let trackingSince = manager.state.bolusReportLedger.trackingSince
        let viewModel = makeViewModel()

        viewModel.doNotLoad()
        viewModel.notLoadedAcknowledged()

        XCTAssertEqual(manager.state.bolusReportLedger.trackingSince, trackingSince)
    }

    func testLoadingShowsProgressAndAFailureKeepsSetupOnTheScreen() {
        let viewModel = makeViewModel()

        viewModel.load()

        XCTAssertEqual(viewModel.phase, .loading)
        waitUntil { viewModel.isShowingLoadFailedAlert }
        XCTAssertTrue(viewModel.isShowingLoadFailedAlert)
        XCTAssertEqual(viewModel.loadFailedMessage, SetupHistoryLoadError.historyUnreadable.localizedDescription)
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertEqual(doneCount, 0)
    }

    func testALoadThatReadsThePumpToItsEndGoesOn() {
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0))
        let viewModel = makeViewModel()

        viewModel.load()

        waitUntil { self.doneCount > 0 }
        XCTAssertEqual(doneCount, 1)
        XCTAssertEqual(viewModel.progress, 1)
        XCTAssertFalse(viewModel.isShowingLoadFailedAlert)
    }
}
