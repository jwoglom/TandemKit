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

    /// The pump reports it has started delivering, stamped with its own start of delivery.
    private func stubDelivering(at deliveryStart: Date) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 1,
            bolusId: Self.bolusId,
            timestamp: UInt32(Dates.fromInstantToJan12008EpochSeconds(deliveryStart)),
            requestedVolume: 2000,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
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

    private func lastFinalizedBolusEvent() -> NewPumpEvent? {
        delegateQueue.sync {}
        return delegate.pumpEvents.last { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
    }

    private func lastFinalizedBolus() -> DoseEntry? {
        lastFinalizedBolusEvent()?.dose
    }

    // MARK: - Natural completion

    /// The whole window comes from the pump: it starts when the pump says delivery started, and
    /// ends when the pump says it ended — five minutes before the driver noticed either.
    func testTheWindowIsThePumpsNotTheDriversDetection() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let deliveryStart = startDate.addingTimeInterval(15)
        let pumpEnd = deliveryStart.addingTimeInterval(58)

        stubDelivering(at: deliveryStart)
        manager.fetchBolusStatus(fromSync: false)

        stubLastBolus(deliveredVolume: 2000, timestamp: pumpEnd)
        stubBolusFinished()
        // The completion poll, not a sync: seeing delivery start pushes the estimated end out,
        // and a sync defers until past that.
        manager.fetchBolusStatus(fromSync: false)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        // The pump's second-resolution timestamps round-trip through its epoch conversion.
        XCTAssertEqual(dose.startDate.timeIntervalSince(deliveryStart), 0, accuracy: 1.0)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
        XCTAssertLessThan(dose.endDate, Date.now.addingTimeInterval(-200))
    }

    func testPumpClockOffsetIsRemovedFromBothEndsOfTheWindow() throws {
        let offset: TimeInterval = .minutes(15)
        let checkedAt = Date.now
        manager.state.currentPumpTime = checkedAt.addingTimeInterval(offset)
        manager.state.lastPumpTimeCheckDate = checkedAt

        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let deliveryStart = startDate.addingTimeInterval(15)
        let pumpEnd = deliveryStart.addingTimeInterval(58)

        stubDelivering(at: deliveryStart.addingTimeInterval(offset))
        manager.fetchBolusStatus(fromSync: false)

        stubLastBolus(deliveredVolume: 2000, timestamp: pumpEnd.addingTimeInterval(offset))
        stubBolusFinished()
        manager.fetchBolusStatus(fromSync: false)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertEqual(dose.startDate.timeIntervalSince(deliveryStart), 0, accuracy: 1.0)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
    }

    /// The dose may start later than the bolus was programmed, but the *event* must keep the date
    /// it was first reported under: hosts key pump events on it, and a moved date reads as a
    /// second bolus rather than as this one finishing.
    func testTheEventDateStaysTheMomentTheBolusWasProgrammed() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let deliveryStart = startDate.addingTimeInterval(15)

        stubDelivering(at: deliveryStart)
        manager.fetchBolusStatus(fromSync: false)

        stubLastBolus(deliveredVolume: 2000, timestamp: deliveryStart.addingTimeInterval(58))
        stubBolusFinished()
        manager.fetchBolusStatus(fromSync: false)

        let event = try XCTUnwrap(lastFinalizedBolusEvent())
        XCTAssertEqual(event.date, startDate)
        XCTAssertGreaterThan(try XCTUnwrap(event.dose).startDate, startDate)
    }

    /// A pump clock ahead of the phone's must not start the dose in the future either.
    func testDeliveryStartIsClampedToNow() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)

        stubDelivering(at: Date.now.addingTimeInterval(3600))
        manager.fetchBolusStatus(fromSync: false)

        stubLastBolus(deliveredVolume: 2000, timestamp: nil)
        stubBolusFinished()
        manager.fetchBolusStatus(fromSync: false)

        let dose = try XCTUnwrap(lastFinalizedBolus())
        XCTAssertLessThanOrEqual(dose.startDate, Date.now)
        XCTAssertGreaterThan(dose.startDate, startDate)
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
            TandemPumpCapabilities.bolusInitiationDelay + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0),
            accuracy: 1e-6
        )
    }

    func testCompletionAfterRelaunchFinalizesThePersistedDose() throws {
        let startDate = trackBolusStarted(secondsAgo: 300, units: 2.0)
        let originalEvent = NewPumpEvent.bolus(
            dose: try XCTUnwrap(manager.state.bolusDose).toDoseEntry(isMutable: true),
            date: startDate
        )
        let restoredState = TandemPumpManagerState(rawValue: manager.state.rawValue)

        manager = TandemPumpManager(state: restoredState, bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        let pumpEnd = startDate.addingTimeInterval(73)
        stubLastBolus(deliveredVolume: 1949, timestamp: pumpEnd)
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        let event = try XCTUnwrap(lastFinalizedBolusEvent())
        XCTAssertEqual(event.raw, originalEvent.raw)
        XCTAssertEqual(event.date, startDate)
        let dose = try XCTUnwrap(event.dose)
        XCTAssertEqual(dose.deliveredUnits, 1.949)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertTrue(bluetooth.didSend(LastBolusStatusRequest.self))
    }

    func testCompletionWithNoLastBolusAnswerDoesNotFinalize() {
        trackBolusStarted(secondsAgo: 300, units: 2.0)
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        stubBolusFinished()

        manager.fetchBolusStatus(fromSync: true)

        XCTAssertNil(lastFinalizedBolus(), "An unknown delivered volume must not be finalized (#328)")
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
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
        let deliveryStart = startDate.addingTimeInterval(15)
        stubDelivering(at: deliveryStart)
        manager.fetchBolusStatus(fromSync: false)
        let pumpEnd = deliveryStart.addingTimeInterval(31)
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

        let event = try XCTUnwrap(lastFinalizedBolusEvent())
        let dose = try XCTUnwrap(event.dose)
        XCTAssertEqual(dose.deliveredUnits, 1.041)
        XCTAssertEqual(dose.startDate.timeIntervalSince(deliveryStart), 0, accuracy: 1.0)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0)
        XCTAssertLessThan(dose.endDate, Date.now.addingTimeInterval(-200))
        // Same identity rule as the completion path.
        XCTAssertEqual(event.date, startDate)
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
            TandemPumpCapabilities.bolusInitiationDelay + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 1.041),
            accuracy: 1e-6
        )
        XCTAssertLessThan(
            dose.endDate.timeIntervalSince(startDate),
            TandemPumpCapabilities.bolusInitiationDelay + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0)
        )
    }
}
