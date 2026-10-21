import LoopKit
@testable import TandemKit
import XCTest

/// A temp basal is replaced by stopping the one that runs and setting the next, and the pump runs
/// its profile in between. The profile over-delivers whenever the temp was below it, so it is the
/// last resort: a request the pump would refuse is made one it accepts before the stop, and a
/// refusal after the stop puts the stopped temp back.
@available(macOS 13.0, iOS 14.0, *) final class TempBasalFallbackTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var delegate: MockPumpManagerDelegate!
    private var queue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock()
        delegate = MockPumpManagerDelegate()
        queue = DispatchQueue(label: "temp-basal-fallback-test")
    }

    override func tearDown() {
        queue = nil
        delegate = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A synced 1.0 U/hr profile on a pump that runs it; the host is attached.
    private func makeManager(
        pumpMilliunits: UInt32 = 1000,
        capMilliunits: UInt32? = nil,
        pumpLimitMilliunits: Int? = nil,
        syncedLimit: Double? = nil
    ) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Double(pumpMilliunits) / 1000)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.maxBasalLimitMilliunits = pumpLimitMilliunits
        state.settings.maxTempBasalRate = syncedLimit
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        bluetooth.stubBasalPump(profileMilliunits: pumpMilliunits, capMilliunits: capMilliunits)
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return manager
    }

    private func enact(_ manager: TandemPumpManager, unitsPerHour: Double, minutes: Double = 30) -> PumpManagerError? {
        var result: PumpManagerError?
        let completed = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: .minutes(minutes)) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)
        queue.sync {}
        return result
    }

    private var sentPercents: [Int] { bluetooth.sent(SetTempRateRequest.self).map(\.percent) }

    private var reportedTempBasals: [DoseEntry] {
        delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .tempBasal }
    }

    private func isRefusal(_ error: PumpManagerError?) -> Bool {
        guard case let .deviceState(underlying?)? = error, case .errorResponse? = underlying as? PumpCommError else { return false }
        return true
    }

    // MARK: - A refused replacement

    /// The 50% temp set five minutes ago had 25 minutes left; the pump refuses its replacement, so
    /// it is set again for those 25 minutes and the host keeps counting 0.5 U/hr, not the profile.
    func testARefusedReplacementPutsTheStoppedTempBasalBackForWhatRemainedOfIt() throws {
        let manager = makeManager()
        XCTAssertNil(enact(manager, unitsPerHour: 0.5))
        clock.advance(by: .minutes(5))
        bluetooth.enqueue(SetTempRateRequest.self, responses: [SetTempRateResponse(status: 7, tempRateId: 0)])

        let error = enact(manager, unitsPerHour: 1.5)

        XCTAssertTrue(isRefusal(error), "\(String(describing: error))")
        XCTAssertEqual(sentPercents, [50, 150, 50])
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).last?.minutes, 25)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 50)
        XCTAssertEqual(manager.state.basalDose.value, 0.5, accuracy: 1e-9)
        XCTAssertEqual(manager.state.basalDose.estimatedEndDate, clock.now.addingTimeInterval(.minutes(25)))
        let restored = try XCTUnwrap(reportedTempBasals.last)
        XCTAssertEqual(restored.unitsPerHour, 0.5, accuracy: 1e-9)
        XCTAssertEqual(restored.startDate, clock.now)
        XCTAssertTrue(restored.isMutable)
    }

    /// The pump takes no temp under 15 minutes, so a stopped temp with 10 left is not set again and
    /// the profile runs those minutes.
    func testARefusedReplacementWithUnderFifteenMinutesLeftLeavesTheProfile() {
        let manager = makeManager()
        XCTAssertNil(enact(manager, unitsPerHour: 0.5))
        clock.advance(by: .minutes(20))
        bluetooth.enqueue(SetTempRateRequest.self, responses: [SetTempRateResponse(status: 7, tempRateId: 0)])

        let error = enact(manager, unitsPerHour: 1.5)

        XCTAssertTrue(isRefusal(error), "\(String(describing: error))")
        XCTAssertEqual(sentPercents, [50, 150])
    }

    /// A zero temp is the one whose loss over-delivers most: the whole profile.
    func testARefusedReplacementOfAZeroTempPutsTheZeroTempBack() {
        let manager = makeManager()
        XCTAssertNil(enact(manager, unitsPerHour: 0, minutes: 60))
        clock.advance(by: .minutes(5))
        bluetooth.enqueue(SetTempRateRequest.self, responses: [SetTempRateResponse(status: 7, tempRateId: 0)])

        XCTAssertTrue(isRefusal(enact(manager, unitsPerHour: 0.3)))

        XCTAssertEqual(sentPercents, [0, 30, 0])
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).last?.minutes, 55)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 0)
        XCTAssertEqual(manager.state.basalDose.value, 0)
    }

    /// A replacement whose answer was lost and that the pump did not run is put back the same way.
    func testAnUnansweredReplacementThatLeftThePumpOnItsProfilePutsTheStoppedTempBasalBack() {
        let manager = makeManager()
        XCTAssertNil(enact(manager, unitsPerHour: 0.5))
        clock.advance(by: .minutes(5))
        bluetooth.enqueue(SetTempRateRequest.self, responses: [nil])

        let error = enact(manager, unitsPerHour: 1.5)

        guard case .communication? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(sentPercents, [50, 150, 50])
        XCTAssertEqual(manager.state.basalDose.tempPercent, 50)
    }

    /// With no temp running there is nothing to put back, and the refusal stands alone.
    func testARefusalWithNoTempRunningSetsNothingElse() {
        let manager = makeManager()
        bluetooth.enqueue(SetTempRateRequest.self, responses: [SetTempRateResponse(status: 7, tempRateId: 0)])

        XCTAssertTrue(isRefusal(enact(manager, unitsPerHour: 1.5)))

        XCTAssertEqual(sentPercents, [150])
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    // MARK: - The pump's maximum basal rate limit

    /// The pump holds a 1.2 U/hr limit, so 1.5 U/hr goes out as 120%, the most it runs, instead of
    /// being refused after the running temp was stopped.
    func testARequestAboveThePumpsLimitRunsAtTheLimit() throws {
        let manager = makeManager(capMilliunits: 1200, pumpLimitMilliunits: 1200)
        XCTAssertNil(enact(manager, unitsPerHour: 0.5))

        XCTAssertNil(enact(manager, unitsPerHour: 1.5))

        XCTAssertEqual(sentPercents, [50, 120])
        XCTAssertEqual(try XCTUnwrap(reportedTempBasals.last).unitsPerHour, 1.2, accuracy: 1e-9)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 120)
    }

    /// Until the pump's own limit has been read, the one the host synced to it stands in.
    func testTheSyncedLimitStandsInUntilThePumpsIsRead() throws {
        let manager = makeManager(capMilliunits: 1200, syncedLimit: 1.2)

        XCTAssertNil(enact(manager, unitsPerHour: 1.5))

        XCTAssertEqual(sentPercents, [120])
        XCTAssertEqual(try XCTUnwrap(reportedTempBasals.last).unitsPerHour, 1.2, accuracy: 1e-9)
    }

    /// The pump's limit is what the firmware enforces, so it wins over a stale synced one.
    func testThePumpsLimitWinsOverTheSyncedOne() {
        let manager = makeManager(pumpLimitMilliunits: 1800, syncedLimit: 1.2)

        XCTAssertNil(enact(manager, unitsPerHour: 1.5))

        XCTAssertEqual(sentPercents, [150])
    }

    func testARequestAtOrUnderTheLimitIsNotClamped() {
        let manager = makeManager(pumpLimitMilliunits: 1200)

        XCTAssertNil(enact(manager, unitsPerHour: 1.2))
        XCTAssertNil(enact(manager, unitsPerHour: 0.5))

        XCTAssertEqual(sentPercents, [120, 50])
    }

    /// A limit that is a hair under the request in Double is the request in milliunits.
    func testTheLimitIsComparedInMilliunits() {
        let manager = makeManager(syncedLimit: 0.57 + 0.01)

        XCTAssertNil(enact(manager, unitsPerHour: 0.58))

        XCTAssertEqual(sentPercents, [58])
    }
}
