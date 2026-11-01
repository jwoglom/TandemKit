import LoopKit
@testable import TandemKit
import XCTest

/// Natural completion with an unknown delivered volume (#328, P22-3).
@available(macOS 13.0, iOS 14.0, *) final class BolusCompletionUnknownDeliveryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 4102
    private static let programmedUnits = 3.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-completion-unknown-delivery-test")
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
    }

    /// bolusId 0 with no delivery in progress is how the pump says the bolus is over.
    private func reportBolusFinished() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: UInt32(Self.programmedUnits * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
        manager.fetchBolusStatus(fromSync: false)
        delegateQueue.sync {}
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

    func testCompletionWithNoLastBolusResponseKeepsTheDoseMutable() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        reportBolusFinished()

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertTrue(lastDose.isMutable, "An unknown delivery must not be finalized")
        XCTAssertNil(lastDose.deliveredUnits)
        XCTAssertFalse(
            reportedBolusDoses.contains { !$0.isMutable },
            "The programmed total must not be reported as the delivered amount"
        )
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testCompletionWithMismatchedBolusIdKeepsTheDoseMutable() throws {
        startBolus()
        stubLastBolus(deliveredVolume: 2900, bolusId: Self.bolusId - 1)

        reportBolusFinished()

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertTrue(lastDose.isMutable)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testMutableReReportKeepsTheRawItWasFirstReportedUnder() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        reportBolusFinished()

        let raws = reportedBolusRaws
        XCTAssertGreaterThanOrEqual(raws.count, 2)
        XCTAssertEqual(raws.first, raws.last)
    }

    func testBolusTrackingStillEndsWhenTheDeliveredVolumeIsUnknown() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        reportBolusFinished()

        XCTAssertNil(manager.state.bolusDose)
        XCTAssertEqual(manager.state.bolusState, .noBolus)
        XCTAssertNil(manager.createBolusProgressReporter(reportingOn: delegateQueue))
    }

    func testRetryFinalizesACompletedBolusWithThePumpsDeliveredVolume() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()

        stubLastBolus(deliveredVolume: 2949)
        manager.finalizePendingBolus()
        delegateQueue.sync {}

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertFalse(lastDose.isMutable)
        XCTAssertEqual(try XCTUnwrap(lastDose.deliveredUnits), 2.949, accuracy: 1e-9)
        XCTAssertEqual(lastDose.programmedUnits, Self.programmedUnits)
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    /// Only one dose is held at a time, so an older one must not be dropped still mutable.
    func testHoldingASecondBolusFinalizesTheFirstWithItsFallback() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()
        manager.state.pendingBolusFinalization?.deliveredUnits = 1.2
        let heldFirst = try XCTUnwrap(manager.state.pendingBolusFinalization)

        let second = UnfinalizedDose(
            units: Self.programmedUnits,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: Self.bolusId + 1
        )
        manager.holdForFinalization(second, fallbackUnits: Self.programmedUnits)
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId + 1)
        let finalized = try XCTUnwrap(reportedBolusDoses.last { !$0.isMutable })
        XCTAssertEqual(try XCTUnwrap(finalized.deliveredUnits), 1.2, accuracy: 1e-9)
        XCTAssertEqual(finalized.startDate, heldFirst.doseStartDate)
    }

    // MARK: - Known delivery still finalizes

    func testCompletionWithAKnownDeliveryFinalizesAtThePumpsVolume() throws {
        startBolus()
        stubLastBolus(deliveredVolume: 2949)

        reportBolusFinished()

        let lastDose = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertFalse(lastDose.isMutable)
        XCTAssertEqual(try XCTUnwrap(lastDose.deliveredUnits), 2.949, accuracy: 1e-9)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertNil(manager.state.bolusDose)
    }
}
