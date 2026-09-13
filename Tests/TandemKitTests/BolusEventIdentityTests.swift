import LoopKit
@testable import TandemKit
import XCTest

/// Every report of one bolus must carry the same `raw`, from enact to finalization (#328, P23-1).
@available(macOS 13.0, iOS 14.0, *) final class BolusEventIdentityTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 5150
    private static let programmedUnits = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-event-identity-test")
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

    private func startBolus() {
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
        manager.enactBolus(units: Self.programmedUnits, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5.0)
        delegateQueue.sync {}
    }

    private func cancelBolus() {
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { result in
            if case .failure(let error) = result {
                XCTFail("cancelBolus failed: \(error)")
            }
            cancelled.fulfill()
        }
        // The cancel path sleeps ~2s to let the pump store the bolus before reading it back.
        wait(for: [cancelled], timeout: 15.0)
        delegateQueue.sync {}
    }

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

    private var bolusEvents: [NewPumpEvent] {
        delegateQueue.sync {}
        return delegate.pumpEvents.filter { $0.dose?.type == .bolus }
    }

    private func assertOneIdentity(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let raws = Set(bolusEvents.map(\.raw))
        XCTAssertEqual(raws.count, 1, "Every report of one bolus must share a raw", file: file, line: line)

        let expected = "bolus \(Self.programmedUnits) "
        let raw = String(data: bolusEvents.first?.raw ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(raw.hasPrefix(expected), "raw \(raw) must be keyed on the programmed amount", file: file, line: line)
    }

    // MARK: - Identity across finalization

    func testCancelledBolusKeepsTheEnactEventsIdentity() {
        startBolus()
        stubLastBolus(deliveredVolume: 1041)

        cancelBolus()

        XCTAssertGreaterThanOrEqual(bolusEvents.count, 2)
        assertOneIdentity()
    }

    func testCompletedBolusKeepsTheEnactEventsIdentity() {
        startBolus()
        stubLastBolus(deliveredVolume: 1949)

        reportBolusFinished()

        XCTAssertGreaterThanOrEqual(bolusEvents.count, 2)
        assertOneIdentity()
    }

    func testBolusFinalizedFromAHeldDoseKeepsTheEnactEventsIdentity() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        cancelBolus()

        stubLastBolus(deliveredVolume: 1041)
        manager.finalizePendingBolus()

        XCTAssertGreaterThanOrEqual(bolusEvents.count, 3)
        assertOneIdentity()
    }

    // MARK: - Zero delivery

    /// Retracting instead would leave Trio holding the programmed amount: it never purges mutable
    /// rows and only shrinks a stored bolus when a smaller one arrives.
    func testZeroDeliveryIsReportedRatherThanRetracted() throws {
        startBolus()
        stubLastBolus(deliveredVolume: 0)

        cancelBolus()

        let finalized = try XCTUnwrap(bolusEvents.compactMap(\.dose).last { !$0.isMutable })
        XCTAssertEqual(finalized.deliveredUnits, 0)
        XCTAssertEqual(finalized.programmedUnits, Self.programmedUnits)
        assertOneIdentity()
    }
}
