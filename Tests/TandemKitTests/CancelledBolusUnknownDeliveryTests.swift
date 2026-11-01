import LoopKit
@testable import TandemKit
import XCTest

/// Cancel with an unknown delivered volume (#328, P05-2).
@available(macOS 13.0, iOS 14.0, *) final class CancelledBolusUnknownDeliveryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 3011
    private static let programmedUnits = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "cancelled-bolus-unknown-delivery-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func stubLastBolus(deliveredVolume: UInt32, bolusId: Int = bolusId) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: bolusId,
            timestamp: 0,
            deliveredVolume: deliveredVolume,
            bolusStatusId: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
    }

    private func startBolus(units: Double = programmedUnits) {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(
            status: 0,
            bolusId: Self.bolusId,
            nackReasonId: 0
        ))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(
            status: 0,
            bolusId: Self.bolusId,
            statusTypeId: 0
        ))

        let enacted = expectation(description: "enactBolus")
        manager.enactBolus(decisionId: nil, units: units, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5.0)
        delegateQueue.sync {}
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
    }

    /// The cancel path sleeps ~2s to let the pump store the bolus before reading it back.
    @discardableResult
    private func cancelBolus() -> DoseEntry? {
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        var returnedDose: DoseEntry?
        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { result in
            switch result {
            case .success(let dose):
                returnedDose = dose
            case .failure(let error):
                XCTFail("cancelBolus failed: \(error)")
            }
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 15.0)
        delegateQueue.sync {}
        return returnedDose
    }

    private var reportedBolusDoses: [DoseEntry] {
        delegateQueue.sync {}
        return delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .bolus }
    }

    private var reportedBolusRaws: [Data] {
        delegateQueue.sync {}
        return delegate.pumpEvents.filter { $0.dose?.type == .bolus }.map(\.raw)
    }

    // MARK: - Unknown delivery is not finalized

    func testCancelWithNoLastBolusResponseKeepsTheDoseMutable() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        let returned = cancelBolus()

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertTrue(lastDose.isMutable, "An unknown delivery must not be finalized")
        XCTAssertNil(lastDose.deliveredUnits, "A mutable dose reports no delivered amount")
        XCTAssertEqual(lastDose.programmedUnits, Self.programmedUnits)

        XCTAssertFalse(
            reportedBolusDoses.contains { !$0.isMutable },
            "No immutable bolus may be reported while the delivered amount is unknown"
        )

        let returnedDose = try XCTUnwrap(returned, "The canceled dose is returned to the host")
        XCTAssertTrue(returnedDose.isMutable)
    }

    func testCancelWithMismatchedBolusIdKeepsTheDoseMutable() throws {
        startBolus()
        stubLastBolus(deliveredVolume: 900, bolusId: Self.bolusId - 1)

        cancelBolus()

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertTrue(lastDose.isMutable)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testMutableReReportKeepsTheRawItWasFirstReportedUnder() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        cancelBolus()

        let raws = reportedBolusRaws
        XCTAssertGreaterThanOrEqual(raws.count, 2)
        XCTAssertEqual(raws.first, raws.last, "The cancel re-report must keep the enact event's raw")
    }

    func testCancelledBolusIsHeldForRetry() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        cancelBolus()

        XCTAssertNil(manager.state.bolusDose, "Delivery is over; only the finalization is pending")
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.value, Self.programmedUnits)
    }

    func testPendingCancelledBolusRoundTripsThroughRawState() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        let restored = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.state.rawValue))

        XCTAssertEqual(restored.pendingBolusFinalization?.bolusId, Self.bolusId)
        XCTAssertEqual(restored.pendingBolusFinalization?.value, Self.programmedUnits)
    }

    // MARK: - Retry

    func testRetryFinalizesWithThePumpsDeliveredVolume() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        stubLastBolus(deliveredVolume: 1041)
        manager.finalizePendingBolus()
        delegateQueue.sync {}

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertFalse(lastDose.isMutable)
        XCTAssertEqual(try XCTUnwrap(lastDose.deliveredUnits), 1.041, accuracy: 1e-9)
        XCTAssertEqual(lastDose.programmedUnits, Self.programmedUnits)
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    func testRetryKeepsWaitingWhileThePumpStaysSilent() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        manager.finalizePendingBolus()
        delegateQueue.sync {}

        XCTAssertFalse(reportedBolusDoses.contains { !$0.isMutable })
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testRetryGivesUpWithTheFallbackAfterTheWindow() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        // Stands in for the elapsed-time estimate the cancel recorded.
        manager.state.pendingBolusFinalization?.deliveredUnits = 0.7

        let afterWindow = Date.now
            .addingTimeInterval(TandemPumpManager.bolusFinalizationWindow + .minutes(1))
        manager.finalizePendingBolus(now: afterWindow)
        delegateQueue.sync {}

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertFalse(lastDose.isMutable)
        XCTAssertEqual(try XCTUnwrap(lastDose.deliveredUnits), 0.7, accuracy: 1e-9)
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    /// A newer bolus's delivery would otherwise be attributed to the held one.
    func testRetryDoesNotReadThePumpWhileAnotherBolusIsTracked() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        startBolus()
        stubLastBolus(deliveredVolume: 1041)
        bluetooth.resetRecordedTraffic()

        manager.finalizePendingBolus()
        delegateQueue.sync {}

        XCTAssertFalse(bluetooth.didSend(LastBolusStatusRequest.self))
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testRetryIsANoOpWithNothingPending() {
        startBolus()
        stubLastBolus(deliveredVolume: 1041)
        cancelBolus()
        let before = reportedBolusDoses.count

        manager.finalizePendingBolus()
        delegateQueue.sync {}

        XCTAssertEqual(reportedBolusDoses.count, before)
    }

    // MARK: - Known delivery still finalizes

    func testCancelWithAKnownDeliveryFinalizesAndReturnsTheDose() throws {
        startBolus()
        stubLastBolus(deliveredVolume: 1041)

        let returned = try XCTUnwrap(cancelBolus(), "The canceled dose is returned to the host")

        XCTAssertFalse(returned.isMutable)
        XCTAssertEqual(try XCTUnwrap(returned.deliveredUnits), 1.041, accuracy: 1e-9)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertNil(manager.state.bolusDose)
    }
}
