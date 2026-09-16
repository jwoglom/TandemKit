import LoopKit
@testable import TandemKit
import XCTest

/// A Tandem temp rate is a percent of the pump's own profile segment, so the percent sent and the
/// rate reported both have to be built from the pump's `profileBasalRate` rather than the host's
/// cached schedule (#335).
@available(macOS 13.0, iOS 14.0, *) final class TempBasalPumpBaselineTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager(hostSchedule: Double) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: hostSchedule)])!
        let state = TandemPumpManagerState(basalRateSchedule: schedule)
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func stubPump(profileBasalRate: Double, basalModifiedBitmask: Int = 0) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: UInt32((profileBasalRate * 1000).rounded()),
            currentBasalRate: UInt32((profileBasalRate * 1000).rounded()),
            basalModifiedBitmask: basalModifiedBitmask
        ))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
    }

    private func enact(
        _ manager: TandemPumpManager,
        unitsPerHour: Double,
        duration: TimeInterval = .minutes(30)
    ) -> PumpManagerError? {
        var result: PumpManagerError?
        let completed = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)
        return result
    }

    private func attach(_ manager: TandemPumpManager) -> (MockPumpManagerDelegate, DispatchQueue) {
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "temp-basal-pump-baseline-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return (delegate, queue)
    }

    private func tempBasalDoses(_ delegate: MockPumpManagerDelegate) -> [DoseEntry] {
        delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .tempBasal }
    }

    // MARK: - The percent is a percent of the pump's profile

    /// The discriminating case: the host thinks the segment is 1.0 U/h but the pump is running a
    /// 2.0 U/h profile. Off the host schedule the request looks like 100 % — no temp rate at all.
    func testPercentIsComputedFromThePumpProfileNotTheHostSchedule() throws {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        stubPump(profileBasalRate: 2.0)

        XCTAssertNil(enact(manager, unitsPerHour: 1.0))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [50])
        let reported = try XCTUnwrap(tempBasalDoses(delegate).last)
        XCTAssertEqual(reported.unitsPerHour, 1.0, accuracy: 1e-9)
    }

    /// The reported rate is the pump's profile times the percent, not the host schedule's.
    func testReportedRateIsThePumpProfileTimesThePercent() throws {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        stubPump(profileBasalRate: 3.0)

        XCTAssertNil(enact(manager, unitsPerHour: 4.5))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [150])
        let reported = try XCTUnwrap(tempBasalDoses(delegate).last)
        XCTAssertEqual(reported.unitsPerHour, 4.5, accuracy: 1e-9)
    }

    /// A pump that reports no profile rate leaves the host schedule as the only baseline there is.
    func testFallsBackToTheHostScheduleWhenThePumpReportsNoProfileRate() throws {
        let manager = makeManager(hostSchedule: 2.0)
        let (delegate, queue) = attach(manager)
        stubPump(profileBasalRate: 0)

        XCTAssertNil(enact(manager, unitsPerHour: 1.0))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [50])
        let reported = try XCTUnwrap(tempBasalDoses(delegate).last)
        XCTAssertEqual(reported.unitsPerHour, 1.0, accuracy: 1e-9)
    }

    /// An empty host schedule is no longer a reason to refuse: the pump knows its own profile.
    func testEnactsWithAnEmptyHostScheduleWhenThePumpReportsAProfileRate() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        _ = attach(manager)
        stubPump(profileBasalRate: 2.0)

        XCTAssertNil(enact(manager, unitsPerHour: 1.0))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [50])
    }

    func testEnactFailsWhenNeitherThePumpNorTheHostHasAProfileRate() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        _ = attach(manager)
        stubPump(profileBasalRate: 0)

        XCTAssertNotNil(enact(manager, unitsPerHour: 1.0))

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    // MARK: - The running temp basal is re-checked against the pump

    private func runningTempBasal(_ manager: TandemPumpManager, rate: Double, duration: TimeInterval = .minutes(30)) {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: rate,
            duration: duration,
            automatic: true,
            insulinType: nil
        )
    }

    private func stubRunningTempBasal(profileBasalRate: Double, currentBasalRate: Double) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: UInt32((profileBasalRate * 1000).rounded()),
            currentBasalRate: UInt32((currentBasalRate * 1000).rounded()),
            basalModifiedBitmask: 0x02
        ))
    }

    /// A profile segment boundary crossed mid-temp-rate keeps the percent but moves the rate under
    /// it. The part already delivered is finalized at the old rate; the remainder is re-reported.
    func testSyncSplitsTheTempBasalWhenThePumpIsRunningADifferentRate() throws {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        runningTempBasal(manager, rate: 1.0)
        stubRunningTempBasal(profileBasalRate: 2.0, currentBasalRate: 2.0)

        manager.fetchBasalStatus()
        queue.sync {}

        let doses = tempBasalDoses(delegate)
        XCTAssertEqual(doses.count, 2)

        let finalized = try XCTUnwrap(doses.first)
        XCTAssertFalse(finalized.isMutable)
        XCTAssertEqual(finalized.unitsPerHour, 1.0, accuracy: 1e-9)

        let corrected = try XCTUnwrap(doses.last)
        XCTAssertTrue(corrected.isMutable)
        XCTAssertEqual(corrected.unitsPerHour, 2.0, accuracy: 1e-9)
        XCTAssertEqual(manager.state.basalDose.value, 2.0, accuracy: 1e-9)
    }

    /// The corrected dose runs out when the original would have, not a fresh 30 minutes later.
    func testTheCorrectedTempBasalKeepsTheOriginalEnd() {
        let manager = makeManager(hostSchedule: 1.0)
        let (_, queue) = attach(manager)
        runningTempBasal(manager, rate: 1.0)
        let originalEnd = manager.state.basalDose.estimatedEndDate
        stubRunningTempBasal(profileBasalRate: 2.0, currentBasalRate: 2.0)

        manager.fetchBasalStatus()
        queue.sync {}

        XCTAssertEqual(
            manager.state.basalDose.estimatedEndDate.timeIntervalSince(originalEnd),
            0,
            accuracy: 1.0
        )
    }

    /// The pump reports at 0.001 U/h while the reported rate is floored onto the 0.01 grid, so a
    /// sub-grid difference is quantisation and must not churn the host's dose history.
    func testSyncLeavesTheTempBasalAloneWhenTheRateMatchesWithinTheGrid() {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        runningTempBasal(manager, rate: 1.01)
        stubRunningTempBasal(profileBasalRate: 1.35, currentBasalRate: 1.0125)

        manager.fetchBasalStatus()
        queue.sync {}

        XCTAssertEqual(tempBasalDoses(delegate).count, 0)
        XCTAssertEqual(manager.state.basalDose.value, 1.01, accuracy: 1e-9)
    }

    /// A pump that reports no rates at all must not split the temp basal down to 0 U/h.
    func testSyncLeavesTheTempBasalAloneWhenThePumpReportsNoProfileRate() {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        runningTempBasal(manager, rate: 1.0)
        stubRunningTempBasal(profileBasalRate: 0, currentBasalRate: 0)

        manager.fetchBasalStatus()
        queue.sync {}

        XCTAssertEqual(tempBasalDoses(delegate).count, 0)
        XCTAssertEqual(manager.state.basalDose.value, 1.0, accuracy: 1e-9)
    }

    /// An expired temp basal is the type-change path's business, not the rate check's.
    func testSyncDoesNotSplitATempBasalThatHasAlreadyRunOut() {
        let manager = makeManager(hostSchedule: 1.0)
        let (delegate, queue) = attach(manager)
        runningTempBasal(manager, rate: 1.0, duration: .minutes(-5))
        stubRunningTempBasal(profileBasalRate: 2.0, currentBasalRate: 2.0)

        manager.fetchBasalStatus()
        queue.sync {}

        XCTAssertEqual(tempBasalDoses(delegate).count, 0)
    }
}
