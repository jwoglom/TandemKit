import LoopKit
@testable import TandemKit
import XCTest

/// The time-gated decisions read `TandemPumpManager.clock`, so a test can cross a 15-minute
/// window or a 4.5-minute throttle without waiting for one.
@available(macOS 13.0, iOS 14.0, *) final class TandemClockInjectionTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    private static let bolusId = 7321
    private static let programmedUnits = 3.0
    private static let start = Date(timeIntervalSinceReferenceDate: 700_000_000)

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.start)
        manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: bluetooth,
            clock: clock
        )
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
    }

    override func tearDown() {
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

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
        manager.waitForDelegateCalls()
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
        manager.waitForDelegateCalls()
    }

    private var reportedBolusDoses: [DoseEntry] {
        manager.waitForDelegateCalls()
        return delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .bolus }
    }

    // MARK: - The finalization window runs on the injected clock

    func testPendingBolusStaysMutableWhileTheClockIsInsideTheFinalizationWindow() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)

        clock.advance(by: TandemPumpManager.bolusFinalizationWindow - 1)
        manager.finalizePendingBolus()

        XCTAssertEqual(
            manager.state.pendingBolusFinalization?.bolusId,
            Self.bolusId,
            "Inside the window the driver keeps waiting for the pump's delivered volume"
        )
        XCTAssertTrue(try XCTUnwrap(reportedBolusDoses.last).isMutable)
    }

    func testPendingBolusFinalizesOnceTheClockPassesTheFinalizationWindow() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()
        manager.state.pendingBolusFinalization?.deliveredUnits = 1.75

        clock.advance(by: TandemPumpManager.bolusFinalizationWindow + 1)
        manager.finalizePendingBolus()

        XCTAssertNil(manager.state.pendingBolusFinalization)
        let finalized = try XCTUnwrap(reportedBolusDoses.last)
        XCTAssertFalse(finalized.isMutable)
        XCTAssertEqual(try XCTUnwrap(finalized.deliveredUnits), 1.75, accuracy: 1e-9)
    }

    /// `holdForFinalization` stamps the start of the retry window, so the window is measured from
    /// the clock's reading at hold time, not from real elapsed time.
    func testTheFinalizationWindowIsMeasuredFromWhenTheDoseWasHeld() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        reportBolusFinished()
        let held = manager.state.pendingBolusFinalization
        XCTAssertEqual(held?.estimatedEndDate, Self.start)
    }

    // MARK: - The sync throttle runs on the injected clock

    func testEnsureCurrentPumpDataSkipsTheSyncWhileTheClockIsInsideTheThrottle() {
        manager.state.lastReconciliation = clock.now
        manager.state.isConnected = true

        clock.advance(by: .minutes(4))
        let done = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { lastSync in
            XCTAssertEqual(lastSync, Self.start)
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0, "Throttled: the pump must not be contacted")
    }

    func testEnsureCurrentPumpDataSyncsInsideTheThrottleWhileTheLinkIsDown() {
        manager.state.lastReconciliation = clock.now
        manager.state.isConnected = false

        clock.advance(by: .minutes(1))
        let done = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in done.fulfill() }
        wait(for: [done], timeout: 5.0)

        XCTAssertGreaterThan(bluetooth.ensureConnectedCount, 0, "A disconnected pump is reconnected by the sync")
    }

    func testEnsureCurrentPumpDataSyncsOnceTheClockPassesTheThrottle() {
        manager.state.lastReconciliation = clock.now

        clock.advance(by: .minutes(5))
        let done = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in done.fulfill() }
        wait(for: [done], timeout: 5.0)

        XCTAssertGreaterThan(bluetooth.ensureConnectedCount, 0, "Past the throttle the sync must run")
    }

    // MARK: - Dose dates come from the injected clock

    func testAnEnactedBolusIsDatedByTheClock() throws {
        startBolus()

        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertEqual(dose.startDate, Self.start)
        XCTAssertEqual(
            dose.estimatedEndDate,
            Self.start.addingTimeInterval(
                manager.estimatedDuration(toBolus: Self.programmedUnits) + TandemPumpCapabilities.bolusInitiationDelay
            )
        )
        XCTAssertEqual(try XCTUnwrap(reportedBolusDoses.last).startDate, Self.start)
        XCTAssertEqual(manager.state.lastReconciliation, Self.start)
    }

    func testASuspendDoseIsDatedByTheClock() throws {
        bluetooth.stub(TempRateRequest.self, with: TempRateResponse(
            active: false,
            percentage: 0,
            startTimeRaw: 0,
            duration: 0
        ))
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))
        clock.advance(by: .hours(2))

        let done = expectation(description: "suspendDelivery")
        manager.suspendDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)
        manager.waitForDelegateCalls()

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(manager.state.basalDose.startDate, Self.start.addingTimeInterval(.hours(2)))
        let suspend = try XCTUnwrap(delegate.pumpEvents.compactMap(\.dose).last { $0.type == .suspend })
        XCTAssertEqual(suspend.startDate, Self.start.addingTimeInterval(.hours(2)))
    }
}
