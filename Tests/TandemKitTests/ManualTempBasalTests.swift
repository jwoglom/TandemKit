import LoopKit
#if canImport(LoopKitUI)
import LoopKitUI
#endif
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class ManualTempBasalTests: XCTestCase {
    private static let pumpSerial: UInt32 = 135_791
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    /// The temp the stub pump runs; nil for its profile.
    private var running: (percent: Int, start: Date, seconds: UInt32)?
    private var nextTempRateId = 41
    /// Status codes for the next `SetTempRate`s, in order; 0 once they run out.
    private var setTempRateStatuses: [Int] = []

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(at(.hours(10)))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func at(_ time: TimeInterval) -> Date {
        Self.referenceDay.addingTimeInterval(time)
    }

    /// `firstRate` U/hr until 14:00 and 2 U/hr after, on the host and the pump alike.
    private func startManager(firstRate: Double = 1.0, maxBasalLimit: Double? = nil) {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: firstRate),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        state.pumpState.pumpSerial = Self.pumpSerial
        state.maxBasalLimitMilliunits = maxBasalLimit.map(TandemPumpCapabilities.milliunits)
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "manual-temp-basal-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            let profile = UInt32((self.manager.getScheduledBasalRate() * 1000).rounded())
            return CurrentBasalStatusResponse(
                profileBasalRate: profile,
                currentBasalRate: profile * UInt32(self.running?.percent ?? 100) / 100,
                basalModifiedBitmask: self.running == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            let status = self.setTempRateStatuses.isEmpty ? 0 : self.setTempRateStatuses.removeFirst()
            guard status == 0, let request = request as? SetTempRateRequest else {
                return SetTempRateResponse(status: status, tempRateId: 0)
            }
            self.running = (request.percent, self.clock.now, UInt32(request.minutes * 60))
            defer { self.nextTempRateId += 1 }
            return SetTempRateResponse(status: 0, tempRateId: self.nextTempRateId)
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.running = nil
            return StopTempRateResponse(status: 0, tempRateId: self.nextTempRateId - 1)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            guard let running = self.running else {
                return TempRateResponse(active: false, percentage: 0, startTimeRaw: 0, duration: 0)
            }
            // The pump's clock is the phone's here unless a test moves `currentPumpTime`.
            let pumpStart = running.start.addingTimeInterval(self.manager.state.pumpClockOffset)
            return TempRateResponse(
                active: true,
                percentage: running.percent,
                startTimeRaw: UInt32(Dates.fromInstantToJan12008EpochSeconds(pumpStart)),
                duration: running.seconds
            )
        }
    }

    private func wait<T>(_ call: (@escaping (T) -> Void) -> Void) -> T {
        let done = expectation(description: "completion")
        var result: T!
        call {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func enactManual(_ percent: Int, for duration: TimeInterval = .minutes(45)) -> PumpManagerError? {
        wait { manager.enactManualTempBasal(percent: percent, duration: duration, completion: $0) }
    }

    private func enactHost(_ unitsPerHour: Double, for duration: TimeInterval = .minutes(30)) -> PumpManagerError? {
        wait { manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration, completion: $0) }
    }

    private func stopFromSettings() -> PumpManagerError? {
        wait { manager.stopTempBasalFromSettings(completion: $0) }
    }

    private func readStatus() throws -> TempRateStatus {
        let result: Result<TempRateStatus, PumpManagerError> = wait { manager.readTempRateStatus(completion: $0) }
        return try result.get()
    }

    private func validationError(_ error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        switch error {
        case let .configuration(underlying?), let .deviceState(underlying?):
            return underlying as? TandemPumpManagerValidationError
        default:
            return nil
        }
    }

    private var reportedTemps: [DoseEntry] {
        delegateQueue.sync {}
        return delegate.pumpEventBatches.flatMap(\.events).compactMap(\.dose).filter { $0.type == .tempBasal }
    }

    // MARK: - Setting one

    func testTheTempGoesOutAtThePercentGivenForWholeMinutesAndIsReportedManual() {
        startManager()

        XCTAssertNil(enactManual(130, for: .minutes(45)))

        let sent = bluetooth.sent(SetTempRateRequest.self)
        XCTAssertEqual(sent.map(\.percent), [130])
        XCTAssertEqual(sent.map(\.minutes), [45])
        let held = manager.state.basalDose
        XCTAssertEqual(held.tempPercent, 130)
        XCTAssertEqual(held.value, 1.3)
        XCTAssertEqual(held.estimatedEndDate, at(.hours(10) + .minutes(45)))
        XCTAssertFalse(held.automatic)
        XCTAssertFalse(held.setByHost)
        XCTAssertEqual(reportedTemps.map(\.automatic), [false])
        XCTAssertTrue(manager.isManualTempRate(41))
    }

    func testOneHundredPercentIsRefusedWithNothingSent() {
        startManager()

        XCTAssertEqual(validationError(enactManual(100)), .manualTempBasalUnchanged)
        XCTAssertTrue(bluetooth.sent(SetTempRateRequest.self).isEmpty)
    }

    func testAPercentOverTheMaxBasalLimitIsRefusedNotClamped() {
        startManager(maxBasalLimit: 2.0)

        XCTAssertEqual(validationError(enactManual(250)), .manualTempBasalOutOfRange(percent: 250, accepted: 10 ... 200))
        XCTAssertTrue(bluetooth.sent(SetTempRateRequest.self).isEmpty)
    }

    func testAPercentUnderThePumpsLowestRateIsRefusedNotRaised() {
        startManager(firstRate: 0.58)

        XCTAssertEqual(validationError(enactManual(17)), .manualTempBasalOutOfRange(percent: 17, accepted: 18 ... 250))
        XCTAssertTrue(bluetooth.sent(SetTempRateRequest.self).isEmpty)
    }

    func testTheBoundsHoldAtEveryProfileRateTheTempRunsAt() {
        clock.set(at(.hours(14) - .minutes(20)))
        startManager(maxBasalLimit: 3.0)

        XCTAssertEqual(manager.manualTempBasalPercents(for: .minutes(15), profileBasalRate: 1.0), 10 ... 250)
        XCTAssertEqual(manager.manualTempBasalPercents(for: .hours(1), profileBasalRate: 1.0), 10 ... 150)
        XCTAssertEqual(validationError(enactManual(160, for: .hours(1))), .manualTempBasalOutOfRange(percent: 160, accepted: 10 ... 150))
        XCTAssertNil(enactManual(150, for: .hours(1)))
    }

    func testAZeroTempIsSetWhateverTheProfile() {
        startManager()
        manager.state.hasSyncedBasalRateSchedule = false

        XCTAssertNil(enactManual(0))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [0])
    }

    func testAnUntrustedPumpClockRefusesANonZeroTemp() {
        startManager()
        manager.state.currentPumpTime = clock.now.addingTimeInterval(.hours(30))
        manager.state.lastPumpTimeCheckDate = clock.now

        XCTAssertEqual(validationError(enactManual(130)), .pumpClockUntrusted)
        XCTAssertTrue(bluetooth.sent(SetTempRateRequest.self).isEmpty)
    }

    // MARK: - A temp in the way

    func testTheLoopsOwnTempIsStoppedAndReplaced() {
        startManager()
        XCTAssertNil(enactHost(1.5))
        clock.advance(by: .minutes(4))

        XCTAssertNil(enactManual(130))

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [150, 130])
        XCTAssertFalse(manager.state.basalDose.automatic)
        XCTAssertEqual(reportedTemps.map(\.automatic), [true, true, false])
    }

    func testARefusedReplacementOfTheLoopsTempPutsItBack() {
        startManager()
        XCTAssertNil(enactHost(1.5))
        clock.advance(by: .minutes(4))
        setTempRateStatuses = [1, 0]

        XCTAssertNotNil(enactManual(130))

        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
        XCTAssertTrue(manager.state.basalDose.setByHost)
        XCTAssertTrue(manager.state.basalDose.automatic)
    }

    func testATempTheHostDidNotSetIsNotReplaced() {
        startManager()
        // Set on the pump's screen: running, but not held.
        running = (120, clock.now, 30 * 60)

        XCTAssertEqual(validationError(enactManual(130)), .tempBasalAlreadyRunning)

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.sent(SetTempRateRequest.self).isEmpty)
    }

    func testAManualTempIsNotReplacedByAnother() {
        startManager()
        XCTAssertNil(enactManual(130))
        clock.advance(by: .minutes(4))

        XCTAssertEqual(validationError(enactManual(150)), .tempBasalAlreadyRunning)

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 130)
    }

    // MARK: - Control-IQ

    func testAManualTempIsSentUnderControlIQ() {
        startManager()
        manager.state.useControlIQ = true

        XCTAssertNil(enactManual(130))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [130])
        XCTAssertFalse(manager.state.basalDose.automatic)
    }

    func testARefusalUnderControlIQSaysControlIQIsOn() throws {
        startManager()
        manager.state.useControlIQ = true
        setTempRateStatuses = [1]

        let error = enactManual(130)

        guard case let .deviceState(underlying?)? = error, case let .errorResponse(context?, _, _)? = underlying as? PumpCommError else {
            return XCTFail("Got \(String(describing: error))")
        }
        XCTAssertTrue(context.contains("Control-IQ is on"), context)
    }

    func testTheStopFromSettingsWorksUnderControlIQWhereTheHostsCancelIsRefused() {
        startManager()
        manager.state.useControlIQ = true
        XCTAssertNil(enactManual(130))
        clock.advance(by: .minutes(10))

        XCTAssertEqual(validationError(enactHost(0, for: 0)), .controlIQModeActive)
        XCTAssertNil(stopFromSettings())

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    // MARK: - Reading the status

    func testWithNoTempRunningTheStatusIsInactive() throws {
        startManager()

        let status = try readStatus()

        XCTAssertFalse(status.isActive)
        XCTAssertNil(status.endDate)
        XCTAssertEqual(status.profileBasalRate, 1.0)
    }

    func testTheLoopsOwnTempReadsAsTheLoopsAndReplaceable() throws {
        startManager()
        XCTAssertNil(enactHost(1.5))
        clock.advance(by: .minutes(5))

        let status = try readStatus()

        XCTAssertEqual(status.percent, 150)
        XCTAssertEqual(status.endDate, at(.hours(10) + .minutes(30)))
        XCTAssertTrue(status.isLoopTemp)
        XCTAssertTrue(status.isReplaceable)
    }

    func testAManualTempReadsAsNotReplaceable() throws {
        startManager()
        XCTAssertNil(enactManual(130))

        let status = try readStatus()

        XCTAssertEqual(status.percent, 130)
        XCTAssertEqual(status.currentBasalRate, 1.3)
        XCTAssertFalse(status.isReplaceable)
    }

    func testTheEndIsRightHoweverFarOffThePumpsClockIs() throws {
        startManager()
        manager.state.currentPumpTime = clock.now.addingTimeInterval(.hours(30))
        manager.state.lastPumpTimeCheckDate = clock.now
        running = (120, clock.now, 75 * 60)

        let status = try readStatus()

        XCTAssertEqual(status.endDate, at(.hours(10) + .minutes(75)))
        XCTAssertFalse(status.isReplaceable)
    }

    // MARK: - Status highlight

    // pumpStatusHighlight lives in TandemKitUI, which has no Linux build.
    #if canImport(SwiftUI)

    func testAManualTempIsSurfacedAsAStatusHighlightUntilItEnds() throws {
        startManager()
        XCTAssertNil(enactManual(130, for: .minutes(30)))

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)
        XCTAssertEqual(highlight.localizedMessage, "Manual Temp Basal")
        XCTAssertEqual(highlight.state, .warning)

        clock.advance(by: .minutes(31))
        XCTAssertNil(manager.pumpStatusHighlight)
    }

    func testTheLoopsTempIsNoStatusHighlight() {
        startManager()
        XCTAssertNil(enactHost(1.5))

        XCTAssertNil(manager.pumpStatusHighlight)
    }

    #endif
}
