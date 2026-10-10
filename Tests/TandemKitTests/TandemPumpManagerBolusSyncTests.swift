import LoopKit
@testable import TandemKit
import XCTest

final class TandemPumpManagerBolusSyncTests: XCTestCase {
    private func makeManager(bolusDose: UnfinalizedDose?) -> TandemPumpManager {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]))
        manager.state.bolusDose = bolusDose
        return manager
    }

    private func makeBolusDose(estimatedEndDate: Date) -> UnfinalizedDose {
        let dose = UnfinalizedDose(
            units: 0.1,
            duration: .seconds(8),
            activationType: .automatic,
            insulinType: nil,
            bolusId: 2004
        )
        dose.estimatedEndDate = estimatedEndDate
        return dose
    }

    func testSyncNotDeferredWithoutTrackedBolus() {
        let manager = makeManager(bolusDose: nil)
        XCTAssertFalse(manager.shouldDeferBolusSync(at: Date()))
    }

    func testSyncDeferredWhileBolusStillExpectedToRun() {
        let now = Date()
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: now.addingTimeInterval(10)))
        XCTAssertTrue(manager.shouldDeferBolusSync(at: now))
    }

    func testSyncDeferredWithinGraceAfterEstimatedEnd() {
        let now = Date()
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: now.addingTimeInterval(-10)))
        XCTAssertTrue(manager.shouldDeferBolusSync(at: now))
    }

    /// Regression: a bolus whose completion event was lost (BLE dropped mid-bolus; the pump
    /// does not replay missed qualifying events) must not defer the sync path forever —
    /// otherwise the stale in-progress state blocks temp basals until the pump is re-paired.
    func testSyncReconcilesAfterGraceExpires() {
        let now = Date()
        let staleEnd = now.addingTimeInterval(-TandemPumpManager.bolusSyncReconcileGrace - 1)
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: staleEnd))
        XCTAssertFalse(manager.shouldDeferBolusSync(at: now))
    }

    // MARK: - A bolus the app did not start

    private static let pumpSerial: UInt32 = 123_456
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private func makeStubbedManager() -> TandemPumpManager {
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(start)
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.pumpSerial
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "untracked-bolus-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    private func bolusStatus(
        _ status: CurrentBolusStatusResponse.CurrentBolusStatus,
        startedSecondsAgo: TimeInterval = 30,
        source: BolusSource = .quickBolus
    ) -> CurrentBolusStatusResponse {
        guard status != .alreadyDeliveredOrInvalid else {
            return CurrentBolusStatusResponse(statusId: status.rawValue, bolusId: 0, timestamp: 0, requestedVolume: 0, bolusSourceId: 0, bolusTypeBitmask: 0)
        }
        return CurrentBolusStatusResponse(
            statusId: status.rawValue,
            bolusId: 42,
            timestamp: UInt32(Dates.fromInstantToJan12008EpochSeconds(clock.now.addingTimeInterval(-startedSecondsAgo))),
            requestedVolume: 2000,
            bolusSourceId: source.rawValue,
            bolusTypeBitmask: 1
        )
    }

    private func readBolusStatus(_ manager: TandemPumpManager, _ response: CurrentBolusStatusResponse) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: response)
        manager.fetchBolusStatus(fromSync: false)
        delegateQueue.sync {}
    }

    private func cancel(_ manager: TandemPumpManager) -> PumpManagerResult<DoseEntry?> {
        var result: PumpManagerResult<DoseEntry?>?
        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus {
            result = $0
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 5)
        delegateQueue.sync {}
        return result!
    }

    func testABolusTheAppDidNotStartIsShownInProgress() throws {
        let manager = makeStubbedManager()

        readBolusStatus(manager, bolusStatus(.delivering, startedSecondsAgo: 30))

        guard case let .inProgress(dose) = manager.state.bolusState else {
            return XCTFail("bolus state is \(manager.state.bolusState)")
        }
        XCTAssertEqual(dose.programmedUnits, 2.0)
        XCTAssertEqual(dose.automatic, false)
        XCTAssertTrue(dose.wasProgrammedByPumpUI)
        XCTAssertEqual(delegate.statusUpdates.last?.newStatus.bolusState, .inProgress(dose))
        let reporter = try XCTUnwrap(manager.createBolusProgressReporter(reportingOn: .main))
        XCTAssertEqual(reporter.progress.deliveredUnits, 30 * TandemPumpCapabilities.bolusSpeedUnder10U, accuracy: 0.001)
        XCTAssertTrue(delegate.pumpEvents.isEmpty, "history reports the dose")
    }

    func testAControlIQBolusIsShownAsAutomatic() {
        let manager = makeStubbedManager()

        readBolusStatus(manager, bolusStatus(.delivering, source: .controlIQAutoBolus))

        guard case let .inProgress(dose) = manager.state.bolusState else {
            return XCTFail("bolus state is \(manager.state.bolusState)")
        }
        XCTAssertEqual(dose.automatic, true)
    }

    func testABolusTheAppDidNotStartIsShownInitiatingWhileRequested() {
        let manager = makeStubbedManager()

        readBolusStatus(manager, bolusStatus(.requesting))

        XCTAssertEqual(manager.state.bolusState, .initiating)
        XCTAssertNotNil(manager.createBolusProgressReporter(reportingOn: .main))
    }

    func testABolusTheAppDidNotStartClearsWithoutADoseOnceItEnds() {
        let manager = makeStubbedManager()
        readBolusStatus(manager, bolusStatus(.delivering))

        readBolusStatus(manager, bolusStatus(.alreadyDeliveredOrInvalid))

        XCTAssertEqual(manager.state.bolusState, .noBolus)
        XCTAssertEqual(delegate.statusUpdates.last?.newStatus.bolusState, .noBolus)
        XCTAssertNil(manager.createBolusProgressReporter(reportingOn: .main))
        XCTAssertTrue(delegate.pumpEvents.isEmpty)
    }

    func testCancelStopsABolusTheAppDidNotStart() {
        let manager = makeStubbedManager()
        readBolusStatus(manager, bolusStatus(.delivering))
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: 42, reasonId: 0))

        let result = cancel(manager)

        guard case let .success(dose) = result else {
            return XCTFail("cancel failed: \(result)")
        }
        XCTAssertNil(dose, "history reports what went in")
        XCTAssertEqual(bluetooth.sent(CancelBolusRequest.self).map(\.bolusId), [42])
        XCTAssertEqual(manager.state.bolusState, .noBolus)
        XCTAssertNil(manager.createBolusProgressReporter(reportingOn: .main))
        XCTAssertTrue(delegate.pumpEvents.isEmpty)
    }

    func testARefusedCancelRereadsTheBolus() {
        let manager = makeStubbedManager()
        readBolusStatus(manager, bolusStatus(.delivering))
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 1, bolusId: 42, reasonId: 2))
        bluetooth.stub(CurrentBolusStatusRequest.self, with: bolusStatus(.alreadyDeliveredOrInvalid))

        let result = cancel(manager)

        guard case .failure = result else {
            return XCTFail("a refused cancel succeeded")
        }
        XCTAssertEqual(manager.state.bolusState, .noBolus, "it had already finished")
    }

    func testWithNoBolusRunningCancelFails() {
        let manager = makeStubbedManager()

        let result = cancel(manager)

        guard case .failure = result else {
            return XCTFail("cancel succeeded with no bolus")
        }
        XCTAssertFalse(bluetooth.didSend(CancelBolusRequest.self))
    }
}
