import LoopKit
@testable import TandemKit
import XCTest

/// The pump contradicting the driver has to be visible, not just logged (#328, P07-3/P23-4/P21-2).
@available(macOS 13.0, iOS 14.0, *) final class PumpDiscrepancyTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 6203
    private static let programmedUnits = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "pump-discrepancy-test")
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

    private func stubLastBolus(
        deliveredVolume: UInt32,
        bolusStatusId: Int = LastBolusStatusAbstractResponse.BolusStatus.complete.rawValue,
        bolusId: Int = bolusId
    ) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: bolusId,
            timestamp: 0,
            deliveredVolume: deliveredVolume,
            bolusStatusId: bolusStatusId,
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

    private func trackTempBasal(rate: Double, endingIn: TimeInterval) {
        let dose = UnfinalizedDose(
            tempRate: rate,
            duration: endingIn,
            automatic: true,
            insulinType: nil
        )
        manager.state.basalDose = dose
    }

    private func stubBasal(currentRate: UInt32, profileRate: UInt32 = 1000, bitmask: Int) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: profileRate,
            currentBasalRate: currentRate,
            basalModifiedBitmask: bitmask
        ))
    }

    // MARK: - Bolus

    func testPumpStoppingABolusForAnAlarmIsRecorded() throws {
        startBolus()
        stubLastBolus(
            deliveredVolume: 900,
            bolusStatusId: LastBolusStatusAbstractResponse.BolusStatus.stoppedAlarm.rawValue
        )

        reportBolusFinished()

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 1)
        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .bolusDeliveryIncomplete)
    }

    /// The pump claiming a complete delivery while reporting less than was asked for.
    func testShortDeliveryReportedAsCompleteIsRecorded() {
        startBolus()
        stubLastBolus(deliveredVolume: 1500)

        reportBolusFinished()

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 1)
        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .bolusDeliveryIncomplete)
    }

    func testAFullDeliveryRecordsNothing() {
        startBolus()
        stubLastBolus(deliveredVolume: 2000)

        reportBolusFinished()

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 0)
        XCTAssertNil(manager.state.lastPumpDiscrepancy)
    }

    /// A cancel is asked for, so the short delivery it produces is not the pump disagreeing.
    func testACancelledBolusIsNotRecordedAsADiscrepancy() {
        startBolus()
        stubLastBolus(
            deliveredVolume: 900,
            bolusStatusId: LastBolusStatusAbstractResponse.BolusStatus.stoppedWireless.rawValue
        )
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { _ in cancelled.fulfill() }
        wait(for: [cancelled], timeout: 15.0)
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 0)
    }

    func testAnAnswerForAnotherBolusIsRecorded() {
        startBolus()
        stubLastBolus(deliveredVolume: 2000, bolusId: Self.bolusId - 1)

        reportBolusFinished()

        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .bolusIdMismatch)
    }

    func testFinalizingFromTheEstimateIsRecorded() {
        manager.state.pendingBolusFinalization = UnfinalizedDose(
            units: Self.programmedUnits,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: Self.bolusId
        )
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        manager.finalizePendingBolus(now: Date.now.addingTimeInterval(.hours(1)))
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .bolusVolumeUnknown)
    }

    // MARK: - Basal

    func testATempBasalThePumpIsNoLongerRunningIsRecorded() {
        trackTempBasal(rate: 1.5, endingIn: .minutes(30))
        stubBasal(currentRate: 1000, bitmask: 0x00)

        manager.fetchBasalStatus()
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .basalMismatch)
    }

    func testATempBasalRunningAtAnotherRateIsRecorded() {
        trackTempBasal(rate: 1.5, endingIn: .minutes(30))
        stubBasal(currentRate: 500, bitmask: 0x02)

        manager.fetchBasalStatus()
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.lastPumpDiscrepancy?.kind, .basalMismatch)
    }

    func testTheRateThePumpAgreesWithRecordsNothing() {
        trackTempBasal(rate: 1.5, endingIn: .minutes(30))
        stubBasal(currentRate: 1500, bitmask: 0x02)

        manager.fetchBasalStatus()
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 0)
    }

    /// A temp basal that simply ran out has not been contradicted.
    func testATempBasalPastItsEndIsNotRecorded() {
        trackTempBasal(rate: 1.5, endingIn: -.minutes(5))
        stubBasal(currentRate: 1000, bitmask: 0x00)

        manager.fetchBasalStatus()
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 0)
    }

    func testTheSameMismatchIsCountedOncePerSync() {
        trackTempBasal(rate: 1.5, endingIn: .minutes(30))
        stubBasal(currentRate: 500, bitmask: 0x02)

        manager.fetchBasalStatus()
        manager.fetchBasalStatus()
        manager.fetchBasalStatus()
        delegateQueue.sync {}

        XCTAssertEqual(manager.state.pumpDiscrepancyCount, 1)
    }

    // MARK: - Persistence

    func testDiscrepanciesSurviveARelaunchAndShowInDebugDescription() throws {
        manager.recordDiscrepancy(.basalMismatch, "detail")

        let restored = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.state.rawValue))

        XCTAssertEqual(restored.pumpDiscrepancyCount, 1)
        XCTAssertEqual(restored.lastPumpDiscrepancy?.kind, .basalMismatch)
        XCTAssertEqual(restored.lastPumpDiscrepancy?.detail, "detail")
        XCTAssertTrue(restored.debugDescription.contains("pumpDiscrepancyCount: 1"))
    }
}
