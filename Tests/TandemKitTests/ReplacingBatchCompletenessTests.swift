import LoopKit
@testable import TandemKit
import XCTest

/// A `replacePendingEvents: true` batch deletes every mutable dose it leaves out, so each one must
/// carry every bolus the host still holds as mutable (#330, #452).
@available(macOS 13.0, iOS 14.0, *) final class ReplacingBatchCompletenessTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 7311
    private static let programmedUnits = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = makeManager(state: TandemPumpManagerState(rawValue: [:]))
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "replacing-batch-completeness-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    // MARK: - Helpers

    private func startBolus(bolusId: Int = bolusId, units: Double = programmedUnits) -> Data? {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: bolusId, statusTypeId: 0))

        let enacted = expectation(description: "enactBolus")
        manager.enactBolus(units: units, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5.0)
        delegateQueue.sync {}
        return delegate.pumpEventBatches.last?.events.first { $0.dose?.type == .bolus }?.raw
    }

    private func stubLastBolus(deliveredVolume: UInt32) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: Self.bolusId,
            timestamp: 0,
            deliveredVolume: deliveredVolume,
            bolusStatusId: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
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

    private func emitReplacingBatch() -> MockPumpManagerDelegate.PumpEventBatch? {
        manager.startScheduledBasalDose()
        delegateQueue.sync {}
        return delegate.pumpEventBatches.last
    }

    private func feedLoop() -> LoopDoseStoreOracle {
        let loop = LoopDoseStoreOracle()
        for batch in delegate.pumpEventBatches {
            loop.addPumpEvents(
                batch.events,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: Date()
            )
        }
        return loop
    }

    // MARK: - App boluses

    func testAReplacingBatchCarriesTheRunningBolus() throws {
        let raw = try XCTUnwrap(startBolus())

        let batch = try XCTUnwrap(emitReplacingBatch())

        XCTAssertTrue(batch.replacePendingEvents)
        let carried = try XCTUnwrap(batch.events.first { $0.raw == raw })
        XCTAssertEqual(carried.dose?.isMutable, true)
        XCTAssertEqual(carried.dose?.programmedUnits, Self.programmedUnits)
    }

    func testAReplacingBatchCarriesABolusHeldForItsDeliveredVolume() throws {
        let raw = try XCTUnwrap(startBolus())
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()
        XCTAssertNotNil(manager.state.pendingBolusFinalization)

        let carried = try XCTUnwrap(emitReplacingBatch()?.events.first { $0.raw == raw })

        XCTAssertEqual(carried.dose?.isMutable, true)
    }

    func testAReplacingBatchCarriesABolusRestoredByARelaunch() throws {
        let raw = try XCTUnwrap(startBolus())

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))

        XCTAssertNotNil(try XCTUnwrap(emitReplacingBatch()).events.first { $0.raw == raw })
    }

    func testTheBatchThatFinalizesTheBolusCarriesItOnce() throws {
        let raw = try XCTUnwrap(startBolus())
        stubLastBolus(deliveredVolume: 1500)

        reportBolusFinished()

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        let reports = batch.events.filter { $0.raw == raw }
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.dose?.isMutable, false)
    }

    func testFinalizingAStaleHeldBolusCarriesTheOneHeldInItsPlace() throws {
        let firstRaw = try XCTUnwrap(startBolus())
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()

        // Another amount: raw is the amount and the start to the second, and both start in one.
        let secondRaw = try XCTUnwrap(startBolus(bolusId: Self.bolusId + 1, units: 1.0))
        reportBolusFinished()

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last { batch in
            batch.events.contains { $0.raw == firstRaw && $0.dose?.isMutable == false }
        })
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.first { $0.raw == secondRaw }?.dose?.isMutable, true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId + 1)
    }

    func testLoopKeepsTheRunningBolusThroughAReplacingBatch() throws {
        // A batch with no dose that outlasts reconciliation never reaches InsulinDeliveryStore.
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 1.5,
            duration: .minutes(30),
            automatic: true,
            insulinType: nil,
            startDate: Date().addingTimeInterval(-.minutes(10))
        )
        let raw = try XCTUnwrap(startBolus())
        _ = emitReplacingBatch()
        XCTAssertEqual(feedLoop().dose(raw: raw)?.isMutable, true)

        stubLastBolus(deliveredVolume: 1500)
        reportBolusFinished()

        let stored = try XCTUnwrap(feedLoop().assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, 1.5)
    }

    func testANonReplacingBatchCarriesNothingExtra() throws {
        let raw = try XCTUnwrap(startBolus())
        let before = delegate.pumpEventBatches.count

        manager.reportReconciliationBoundary()
        delegateQueue.sync {}

        let batch = try XCTUnwrap(delegate.pumpEventBatches.dropFirst(before).first)
        XCTAssertFalse(batch.replacePendingEvents)
        XCTAssertFalse(batch.events.contains { $0.raw == raw })
    }
}
