import LoopKit
@testable import TandemKit
import XCTest

/// A bolus that completes while the link is down is finalized whenever the driver next reaches
/// the pump — up to a whole sync later, and after a reconnect much later than that. The finalized
/// dose must still be dated by the pump's record of when delivery ended, not by that detection,
/// or LoopKit models the insulin as trickling in across the whole gap (#339).
@available(macOS 13.0, iOS 14.0, *) final class BolusEndDateReportingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 2004

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-end-date-test")
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

    /// Puts the driver in the state it would be in if a bolus had been programmed
    /// `startedSecondsAgo` ago and the link had been down since — which is the only way to get a
    /// detection that is meaningfully later than the start within a test.
    @discardableResult
    private func trackBolusStarted(secondsAgo: TimeInterval, units: Double) -> Date {
        let startDate = Date.now.addingTimeInterval(-secondsAgo)
        let dose = UnfinalizedDose(rawValue: [
            "type": DoseType.bolus.rawValue,
            "value": units,
            "startDate": startDate,
            "estimatedEndDate": startDate.addingTimeInterval(manager.estimatedDuration(toBolus: units)),
            "deliveredUnits": 0.0,
            "automatic": false,
            "bolusId": Self.bolusId
        ])!

        manager.state.bolusDose = dose
        manager.state.bolusState = .inProgress(dose.toDoseEntry(isMutable: true))
        manager.bolusProgressReport = TandemDoseProgressReporter(
            pumpManager: manager,
            dose: dose.toDoseEntry(isMutable: true),
            activationType: .manualNoRecommendation
        )
        return startDate
    }

    private func stubLastBolus(deliveredVolume: UInt32, timestamp: Date?) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: Self.bolusId,
            timestamp: timestamp.map { UInt32(Dates.fromInstantToJan12008EpochSeconds($0)) } ?? 0,
            deliveredVolume: deliveredVolume,
            bolusStatusId: LastBolusStatusAbstractResponseBolusStatus.complete.rawValue,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
    }

    /// The pump reports the bolus is over: no delivery in progress, and no bolus id.
    private func stubBolusFinished() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: 2000,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    private func lastFinalizedBolus() -> DoseEntry? {
        delegateQueue.sync {}
        return delegate.pumpEvents
            .compactMap(\.dose)
            .last { $0.type == .bolus && !$0.isMutable }
    }

    // MARK: - Natural completion

    func testCompletionIsDatedByThePumpNotByTheDetection() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let pumpEnd = startDate.addingTimeInterval(58)
        stubLastBolus(deliveredVolume: 2000, timestamp: pumpEnd)
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(dose.startDate, startDate)
        // The pump's second-resolution timestamp round-trips through its epoch conversion.
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
        XCTAssertLessThan(dose.endDate, Date.now.addingTimeInterval(-200))
    }

    /// Without a usable pump timestamp the window still has to come from the delivery, not from
    /// the five minutes the driver spent unaware the bolus had ended.
    func testCompletionWithoutAPumpTimestampUsesTheDeliveryRate() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        stubLastBolus(deliveredVolume: 2000, timestamp: nil)
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(
            dose.endDate.timeIntervalSince(startDate),
            BolusEndDate.estimatedDuration(toBolus: 2.0),
            accuracy: 1e-6
        )
    }

    /// The pump never answered the last-bolus read: full delivery is assumed for the volume, and
    /// the window has to follow from that same assumption rather than from the detection.
    func testCompletionWithNoLastBolusAnswerUsesTheProgrammedVolume() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(dose.deliveredUnits, 2.0)
        XCTAssertEqual(
            dose.endDate.timeIntervalSince(startDate),
            BolusEndDate.estimatedDuration(toBolus: 2.0),
            accuracy: 1e-6
        )
    }

    /// A pump clock ahead of the phone's must not date delivery into the future.
    func testCompletionNeverEndsAfterTheDetection() throws {
        trackBolusStarted(secondsAgo: 300, units: 2.0)
        stubLastBolus(deliveredVolume: 2000, timestamp: Date.now.addingTimeInterval(3600))
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertLessThanOrEqual(dose.endDate, Date.now)
    }

    // MARK: - Cancellation

    func testCancelledBolusIsDatedByThePumpNotByTheCancelRoundTrip() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let pumpEnd = startDate.addingTimeInterval(31)
        stubLastBolus(deliveredVolume: 1041, timestamp: pumpEnd)
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

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(dose.deliveredUnits, 1.041)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
        XCTAssertLessThan(dose.endDate, Date.now.addingTimeInterval(-200))
    }

    /// Cancelled after 1.041 U of a 2 U bolus: the window is the one that volume took, not the
    /// programmed bolus's.
    func testCancelledBolusWithoutAPumpTimestampUsesTheDeliveredVolume() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        stubLastBolus(deliveredVolume: 1041, timestamp: nil)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { _ in cancelled.fulfill() }
        wait(for: [cancelled], timeout: 15.0)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(
            dose.endDate.timeIntervalSince(startDate),
            BolusEndDate.estimatedDuration(toBolus: 1.041),
            accuracy: 1e-6
        )
        XCTAssertLessThan(
            dose.endDate.timeIntervalSince(startDate),
            BolusEndDate.estimatedDuration(toBolus: 2.0)
        )
    }
}
