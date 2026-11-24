import LoopKit
#if canImport(LoopKitUI)
import LoopKitUI
#endif
@testable import TandemKit
import XCTest

/// Covers the pre-flight checks `enactBolus` runs before it touches the pump. The pump enforces
/// its own max bolus limit too; these guards exist so an out-of-range request fails fast with a
/// specific error rather than as a generic mid-handshake rejection.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerValidationTests: XCTestCase {
    private func makeManager(settings: TandemPumpManagerSettings) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.settings = settings
        return TandemPumpManager(state: state)
    }

    func testBolusExceedingMaxBolusIsRejected() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertEqual(
            manager.validateBolusRequest(units: 6.0),
            .maximumBolusExceeded(requested: 6.0, maximum: 5.0)
        )
    }

    func testBolusAtMaxBolusIsAllowed() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertNil(manager.validateBolusRequest(units: 5.0))
    }

    func testNonPositiveBolusIsRejected() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        XCTAssertEqual(manager.validateBolusRequest(units: 0), .invalidBolusAmount(requested: 0))
        XCTAssertEqual(manager.validateBolusRequest(units: -1.0), .invalidBolusAmount(requested: -1.0))
    }

    /// Until the host app syncs delivery limits there is no maximum to check against, so only the
    /// positive-amount guard applies — the pump remains the backstop.
    func testUnsyncedDeliveryLimitsOnlyEnforcePositiveAmount() {
        let manager = makeManager(settings: TandemPumpManagerSettings())

        XCTAssertNil(manager.validateBolusRequest(units: 25.0))
        XCTAssertEqual(manager.validateBolusRequest(units: 0), .invalidBolusAmount(requested: 0))
    }

    func testEnactBolusSurfacesValidationErrorAsDeviceState() {
        let manager = makeManager(settings: TandemPumpManagerSettings(maxBolus: 5.0))

        let expectation = expectation(description: "Bolus completion")
        manager.enactBolus(decisionId: nil, units: 6.0, activationType: .manualNoRecommendation) { error in
            guard case let .deviceState(underlyingError?) = error,
                  let validationError = underlyingError as? TandemPumpManagerValidationError
            else {
                XCTFail("Expected deviceState validation error, received: \(String(describing: error))")
                expectation.fulfill()
                return
            }

            XCTAssertEqual(validationError, .maximumBolusExceeded(requested: 6.0, maximum: 5.0))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Control-IQ

    private func makeControlIQManager() -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.settings = TandemPumpManagerSettings(maxBolus: 5.0)
        state.useControlIQ = true
        return TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())
    }

    private func validationError(from error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .deviceState(underlyingError?) = error else { return nil }
        return underlyingError as? TandemPumpManagerValidationError
    }

    func testAutomaticBolusIsBlockedWhileControlIQIsActive() {
        let manager = makeControlIQManager()

        let expectation = expectation(description: "Bolus completion")
        var error: PumpManagerError?
        manager.enactBolus(decisionId: nil, units: 1.0, activationType: .automatic) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(validationError(from: error), .controlIQModeActive)
    }

    func testTempBasalIsBlockedWhileControlIQIsActive() {
        let manager = makeControlIQManager()

        let expectation = expectation(description: "Temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(validationError(from: error), .controlIQModeActive)
    }

    // MARK: - Basal schedule never synced

    private func makeUnsyncedManager(bluetooth: StubPumpBluetooth) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        return TandemPumpManager(state: TandemPumpManagerState(basalRateSchedule: schedule), bluetooth: bluetooth)
    }

    private func enactTempBasal(_ manager: TandemPumpManager, unitsPerHour: Double, for duration: TimeInterval) -> PumpManagerError? {
        let expectation = expectation(description: "Temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: duration) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return error
    }

    func testTempBasalIsBlockedUntilTheBasalScheduleHasSynced() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30))

        guard case let .configuration(underlying?) = error else {
            return XCTFail("Expected a configuration error, got \(String(describing: error))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .basalScheduleNotSynced)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testTempBasalIsRefusedWhileThePumpProfileIsUpdatedToTheSchedule() {
        let bluetooth = StubPumpBluetooth()
        let pump = StubIDPPump([.init(startTime: 0, basalRate: 900)])
        pump.install(on: bluetooth)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30))

        guard case let .configuration(underlying?) = error else {
            return XCTFail("Expected a configuration error, got \(String(describing: error))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .basalScheduleNotSynced)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertEqual(pump.segments.map(\.basalRate), [1000], "the update queued behind the refused temp")
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testTempBasalGoesOutWhenThePumpProfileAlreadyMatchesTheSchedule() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 1000)]).install(on: bluetooth)
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30)))
        XCTAssertTrue(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetIDPSegmentRequest.self))
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testTempBasalCancelIsAllowedBeforeTheBasalScheduleHasSynced() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 2000,
            basalModifiedBitmask: 0x02
        ))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 7))
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: 0))
        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
    }

    // MARK: - Pump profile at 0 U/hr

    private func makeSyncedManager(bluetooth: StubPumpBluetooth, pumpBasal: CurrentBasalStatusResponse) -> TandemPumpManager {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: pumpBasal)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 7))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 8))
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.hasSyncedBasalRateSchedule = true
        return manager
    }

    /// The field report: a synced driver, a Mobi whose active profile reads 0 U/hr, Trio asking for 1.46.
    func testTempBasalIsRefusedWhenThePumpProfileRateIsZero() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0
        ))

        let error = enactTempBasal(manager, unitsPerHour: 1.46, for: .minutes(30))

        XCTAssertEqual(validationError(from: error), .pumpProfileBasalRateIsZero)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertNotEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testRefusalOnAZeroProfileLeavesTheRunningTempBasalAlone() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0x02
        ))

        let error = enactTempBasal(manager, unitsPerHour: 1.46, for: .minutes(30))

        XCTAssertEqual(validationError(from: error), .pumpProfileBasalRateIsZero)
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    // MARK: - Zero temp basal

    private func zeroTempGoesOut(_ manager: TandemPumpManager, _ bluetooth: StubPumpBluetooth) {
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: .minutes(30)))
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [0])
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [30])
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 0)
    }

    func testZeroTempBasalGoesOutOnAZeroRatePumpProfile() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 0)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.hasSyncedBasalRateSchedule = true

        zeroTempGoesOut(manager, bluetooth)
    }

    func testZeroTempBasalGoesOutBeforeTheBasalScheduleHasSynced() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 900)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        zeroTempGoesOut(manager, bluetooth)
        XCTAssertFalse(bluetooth.didSend(ProfileStatusRequest.self), "no profile read for a zero temp")
    }

    func testZeroTempBasalGoesOutAfterAFailedProfileUpdate() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 1400)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        zeroTempGoesOut(manager, bluetooth)
    }

    func testZeroTempBasalGoesOutWithNoHostSchedule() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 900)
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        zeroTempGoesOut(manager, bluetooth)
    }

    func testZeroTempBasalIsRefusedWhileControlIQIsActive() {
        let manager = makeControlIQManager()

        XCTAssertEqual(validationError(from: enactTempBasal(manager, unitsPerHour: 0, for: .minutes(30))), .controlIQModeActive)
    }

    func testTempBasalCancelGoesThroughWhenThePumpProfileRateIsZero() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0x02
        ))

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: 0))
        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
    }

    func testTempBasalIsRefusedOnAZeroProfileWhileSuspended() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0x01
        ))

        let error = enactTempBasal(manager, unitsPerHour: 1.46, for: .minutes(30))

        XCTAssertEqual(validationError(from: error), .pumpProfileBasalRateIsZero)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testTempBasalGoesOutOnANonZeroPumpProfile() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.hasSyncedBasalRateSchedule = true
        bluetooth.stubBasalPump(profileMilliunits: 1000)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.46, for: .minutes(30)))
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [146])
    }

    // MARK: - Failed basal profile update

    func testTempBasalIsRefusedAfterAFailedUpdateEvenThoughThePumpProfileMatches() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 1000)]).install(on: bluetooth)
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 1400,
            currentBasalRate: 1400,
            basalModifiedBitmask: 0
        ))
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.verifyDeliveredBasalRate(CurrentBasalStatusResponse(
            profileBasalRate: 1400,
            currentBasalRate: 1400,
            basalModifiedBitmask: 0
        ))
        XCTAssertTrue(manager.state.basalProfileUpdateFailed)
        bluetooth.resetRecordedTraffic()

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30))

        guard case let .configuration(underlying?) = error else {
            return XCTFail("Expected a configuration error, got \(String(describing: error))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .failedUpdatePumpProfile)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertFalse(bluetooth.didSend(IDPSegmentRequest.self), "a matching profile is not read to re-adopt it")
    }

    func testTempBasalGoesOutAgainOnceARetryReadsTheProfileBackMatching() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 1000)]).install(on: bluetooth)
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        let matching = CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: 1000, basalModifiedBitmask: 0)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        manager.verifyDeliveredBasalRate(matching)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30)))
        XCTAssertTrue(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    // MARK: - Temp basal read back after it is set

    private func status(profile: UInt32, current: UInt32, bitmask: Int) -> CurrentBasalStatusResponse {
        CurrentBasalStatusResponse(profileBasalRate: profile, currentBasalRate: current, basalModifiedBitmask: bitmask)
    }

    func testReadbackMatchesThePercentOfThePumpsRate() {
        XCTAssertTrue(TandemPumpManager.tempBasalReadbackMatches(status(profile: 1100, current: 1463, bitmask: 0x02), percent: 133))
    }

    func testReadbackMatchesAPumpThatRoundsWithinOneStep() {
        for current: UInt32 in [1460, 1470] {
            XCTAssertTrue(
                TandemPumpManager.tempBasalReadbackMatches(status(profile: 1100, current: current, bitmask: 0x02), percent: 133),
                "\(current) mU/hr"
            )
        }
    }

    /// 10% of 0.15 U/hr is 0.015, below the 0.1 U/hr floor the reported grid rounds onto.
    func testReadbackMatchesEitherSideOfTheGapBelowTheMinimumRate() {
        for current: UInt32 in [0, 15] {
            XCTAssertTrue(
                TandemPumpManager.tempBasalReadbackMatches(status(profile: 150, current: current, bitmask: 0x02), percent: 10),
                "\(current) mU/hr"
            )
        }
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(status(profile: 150, current: 100, bitmask: 0x02), percent: 10))
    }

    func testReadbackMoreThanOneStepOffThePercentDoesNotMatch() {
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(status(profile: 1100, current: 1263, bitmask: 0x02), percent: 133))
    }

    func testReadbackWithNoTempRunningDoesNotMatch() {
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(status(profile: 1460, current: 1460, bitmask: 0), percent: 100))
    }

    private func makeReadbackManager(bluetooth: StubPumpBluetooth) -> (TandemPumpManager, MockPumpManagerDelegate, DispatchQueue) {
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.hasSyncedBasalRateSchedule = true
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "temp-basal-readback-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return (manager, delegate, queue)
    }

    private func reportedTempBasalRates(_ delegate: MockPumpManagerDelegate) -> [Double] {
        delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .tempBasal }.map(\.unitsPerHour)
    }

    func testTempBasalIsReportedWhenThePumpRunsTheCommandedRate() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))
        queue.sync {}

        XCTAssertEqual(reportedTempBasalRates(delegate), [1.5])
        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
    }

    /// A pump the driver does not know the max basal limit of caps the 150% temp at 1.2 U/hr. What
    /// runs is kept and told to the host; stopping it would put the pump on its 1.0 U/hr profile.
    func testMismatchedReadbackKeepsTheTempBasalAtThePumpsRateAndFails() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 1000, capMilliunits: 1200)
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))
        queue.sync {}

        XCTAssertEqual(validationError(from: error), .tempBasalRateMismatch(expected: 1.5, actual: 1.2))
        let sent = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        XCTAssertEqual(
            sent.filter { $0.contains("TempRate") || $0 == "CurrentBasalStatusRequest" },
            ["CurrentBasalStatusRequest", "SetTempRateRequest", "CurrentBasalStatusRequest"]
        )
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 1.2, accuracy: 0.0001)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
        XCTAssertEqual(reportedTempBasalRates(delegate), [1.2])
    }

    func testReadbackWithNoTempRunningFailsWithoutAStop() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stub(CurrentBasalStatusRequest.self, with: status(profile: 1000, current: 1000, bitmask: 0))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))
        queue.sync {}

        XCTAssertEqual(validationError(from: error), .tempBasalRateMismatch(expected: 1.5, actual: 1.0))
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(reportedTempBasalRates(delegate), [])
    }

    func testTempBasalIsReportedAsCommandedWhenTheReadbackGetsNoAnswer() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.enqueue(CurrentBasalStatusRequest.self, responses: [status(profile: 1000, current: 1000, bitmask: 0), nil])
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))
        queue.sync {}

        XCTAssertEqual(reportedTempBasalRates(delegate), [1.5])
    }

    // MARK: - Percent baseline

    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))

    /// Schedule 1.0 U/hr until 14:00 and 2.0 after, synced; the pump runs `pumpMilliunits`.
    private func makeBaselineManager(at time: TimeInterval, pumpMilliunits: UInt32, bluetooth: StubPumpBluetooth) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = ManualClock(Self.referenceDay.addingTimeInterval(time))
        bluetooth.stubBasalPump(profileMilliunits: pumpMilliunits)
        return manager
    }

    func testThePercentIsWorkedOutAgainstThePumpsRate() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 800, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [188])
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    func testMoreThanFiveMinutesBeforeARiseTheTempUsesTheRateInForce() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(6), pumpMilliunits: 1000, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [150])
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    /// 75% runs 0.75 U/hr until 14:00 and 1.5 after; the host is told 1.5 throughout.
    func testWithinFiveMinutesOfARiseTheTempIsWorkedOutAgainstTheNextRate() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(4), pumpMilliunits: 1000, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [75])
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    func testWithinFiveMinutesOfAFallTheTempUsesTheRateInForce() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(24) - .minutes(4), pumpMilliunits: 2000, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [75])
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    /// Phone at 13:50, pump clock 11 minutes ahead at 14:01: the pump is past its change already.
    func testTheChangeIsLookedUpOnThePumpsClock() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(10), pumpMilliunits: 2000, bluetooth: bluetooth)
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(.minutes(11))

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [75])
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    func testHostDateAppliesAnOffsetUpToADay() {
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: StubPumpBluetooth())
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(.hours(3))

        XCTAssertEqual(manager.hostDate(forPumpDate: manager.now), manager.now.addingTimeInterval(-.hours(3)))
    }

    func testHostDateIgnoresAnOffsetOverADay() {
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: StubPumpBluetooth())
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(-4_294_967)

        XCTAssertEqual(manager.hostDate(forPumpDate: manager.now), manager.now)
    }

    // MARK: - A pump clock more than a day off the phone's

    /// #503: one read came 2^32 ms behind the phone.
    private static let twoToThe32MsShort: TimeInterval = -4_294_967

    private func setPumpClockOffset(_ manager: TandemPumpManager, _ offset: TimeInterval) {
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(offset)
    }

    private func enactBolus(_ manager: TandemPumpManager, units: Double, _ activationType: BolusActivationType) -> PumpManagerError? {
        let expectation = expectation(description: "Bolus completion")
        var error: PumpManagerError?
        manager.enactBolus(decisionId: nil, units: units, activationType: activationType) {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return error
    }

    func testBolusesAreRefusedWhileThePumpsClockIsOverADayOff() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        for type in [BolusActivationType.manualNoRecommendation, .manualRecommendationAccepted, .automatic] {
            XCTAssertEqual(validationError(from: enactBolus(manager, units: 1.0, type)), .pumpClockUntrusted, "\(type)")
        }
        XCTAssertFalse(bluetooth.didSend(BolusPermissionRequest.self))
    }

    func testTempBasalsAreRefusedWhileThePumpsClockIsOverADayOff() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        XCTAssertEqual(validationError(from: enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))), .pumpClockUntrusted)
        XCTAssertEqual(validationError(from: enactTempBasal(manager, unitsPerHour: 0.5, for: .minutes(30))), .pumpClockUntrusted)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testAZeroTempAndACancelStillGoOutWhileThePumpsClockIsOverADayOff() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: .minutes(30)))
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: 0))
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [0])
    }

    func testTempBasalsGoOutOnceAClockReadIsWithinADay() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 800, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)
        XCTAssertEqual(validationError(from: enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))), .pumpClockUntrusted)

        bluetooth.stub(TimeSinceResetRequest.self, with: TimeSinceResetResponse(
            currentTime: UInt32(Dates.fromInstantToJan12008EpochSeconds(manager.now)),
            pumpTimeSinceReset: 600
        ))
        manager.fetchTimeSinceReset()

        XCTAssertFalse(manager.state.isPumpClockUntrusted)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))
    }

    func testAZoneSizedOffsetDoesNotBlockDosing() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 800, bluetooth: bluetooth)
        setPumpClockOffset(manager, .hours(3))

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))
    }

    func testNoClockSkewTempIsStartedOnAClockOverADayOff() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(5), pumpMilliunits: 2000, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        manager.fetchBasalStatus()

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertNil(manager.skewCompensationTemp)
    }

    func testAClockSkewTempRunningWhenTheClockGoesOverADayOffIsStopped() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.fetchBasalStatus()
        XCTAssertEqual(manager.skewCompensationTemp?.percent, 50)

        setPumpClockOffset(manager, Self.twoToThe32MsShort)
        manager.fetchBasalStatus()

        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertNil(manager.skewCompensationTemp)
    }

    /// Phone 13:55 with the pump on the 1.0 U/hr segment; an offset of 49 days 17 h puts the schedule lookup in the 2.0 segment.
    func testNoBasalRateMismatchIsNotedOnAClockOverADayOff() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(5), pumpMilliunits: 1000, bluetooth: bluetooth)
        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        manager.fetchBasalStatus()

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testNoPumpSegmentChangesAreFoundOnAClockOverADayOff() {
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: StubPumpBluetooth())
        let through = manager.now.addingTimeInterval(.hours(6))
        setPumpClockOffset(manager, 0)
        XCTAssertEqual(manager.pumpSegmentChanges(after: manager.now, through: through).count, 1)

        setPumpClockOffset(manager, Self.twoToThe32MsShort)

        XCTAssertEqual(manager.pumpSegmentChanges(after: manager.now, through: through).count, 0)
    }

    func testPumpSegmentChangesAreDatedOnThePhonesClock() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(13), pumpMilliunits: 1000, bluetooth: bluetooth)
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(.minutes(11))

        let changes = manager.pumpSegmentChanges(after: manager.now, through: manager.now.addingTimeInterval(.hours(12)))

        XCTAssertEqual(changes.map(\.date), [
            Self.referenceDay.addingTimeInterval(.hours(14) - .minutes(11)),
            Self.referenceDay.addingTimeInterval(.hours(24) - .minutes(11))
        ])
        XCTAssertEqual(changes.map(\.rate), [2.0, 1.0])
    }

    // MARK: - Temp basal across a pump segment change

    private func attachDelegate(_ manager: TandemPumpManager) -> (MockPumpManagerDelegate, DispatchQueue) {
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "segment-change-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return (delegate, queue)
    }

    private func at(_ time: TimeInterval) -> Date {
        Self.referenceDay.addingTimeInterval(time)
    }

    private func tempBasals(_ delegate: MockPumpManagerDelegate, _ queue: DispatchQueue) -> [DoseEntry] {
        queue.sync {}
        return delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .tempBasal }
    }

    func testATempCrossingARiseIsCutAtTheChangeOnTheNextReading() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(20), pumpMilliunits: 1000, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        manager.clock = ManualClock(at(.hours(14) + .minutes(3)))
        manager.fetchBasalStatus()

        let doses = tempBasals(delegate, queue).suffix(2)
        XCTAssertEqual(doses.map(\.startDate), [at(.hours(14) - .minutes(20)), at(.hours(14))])
        XCTAssertEqual(doses.map(\.unitsPerHour), [1.5, 3.0])
        XCTAssertEqual(doses.map(\.isMutable), [false, true])
        XCTAssertEqual(doses.first?.endDate, at(.hours(14)))
        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(14)))
        XCTAssertEqual(manager.state.basalDose.estimatedEndDate, at(.hours(14) + .minutes(10)))
        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
    }

    func testATempCrossingAFallIsCutAtTheChangeOnTheNextReading() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(24) - .minutes(20), pumpMilliunits: 2000, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        manager.clock = ManualClock(at(.hours(24) + .minutes(3)))
        manager.fetchBasalStatus()

        XCTAssertEqual(tempBasals(delegate, queue).suffix(2).map(\.unitsPerHour), [1.5, 0.75])
        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(24)))
    }

    /// Set four minutes before the rise at 75%, so it already runs the 1.5 recorded once the rate rises.
    func testATempSetWithinFiveMinutesOfARiseIsNotCutAtIt() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(4), pumpMilliunits: 1000, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))
        let reported = tempBasals(delegate, queue).count

        manager.clock = ManualClock(at(.hours(14) + .minutes(1)))
        manager.fetchBasalStatus()

        XCTAssertEqual(tempBasals(delegate, queue).count, reported)
        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(14) - .minutes(4)))
    }

    func testAZeroTempIsNeverCut() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(20), pumpMilliunits: 1000, bluetooth: bluetooth)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: .minutes(30)))

        manager.clock = ManualClock(at(.hours(14) + .minutes(3)))
        manager.fetchBasalStatus()

        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(14) - .minutes(20)))
        XCTAssertEqual(manager.state.basalDose.value, 0)
    }

    func testATempReplacedAfterCrossingAChangeIsReportedInTwoParts() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(20), pumpMilliunits: 1000, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        manager.clock = ManualClock(at(.hours(14) + .minutes(3)))
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.2, for: .minutes(30)))

        let finished = tempBasals(delegate, queue).filter { !$0.isMutable }
        XCTAssertEqual(finished.map(\.startDate), [at(.hours(14) - .minutes(20)), at(.hours(14))])
        XCTAssertEqual(finished.map(\.endDate), [at(.hours(14)), at(.hours(14) + .minutes(3))])
        XCTAssertEqual(finished.map(\.unitsPerHour), [1.5, 3.0])
    }

    func testATempThePumpEndsAfterCrossingAChangeIsReportedInTwoParts() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(20), pumpMilliunits: 1000, bluetooth: bluetooth)
        manager.state.featureFlags[.historyBackfill] = false
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        manager.clock = ManualClock(at(.hours(14) + .minutes(3)))
        bluetooth.stub(CurrentBasalStatusRequest.self, with: status(profile: 2000, current: 2000, bitmask: 0))
        manager.fetchBasalStatus()

        let finished = tempBasals(delegate, queue).filter { !$0.isMutable }
        XCTAssertEqual(finished.map(\.startDate), [at(.hours(14) - .minutes(20)), at(.hours(14))])
        XCTAssertEqual(finished.map(\.unitsPerHour), [1.5, 3.0])
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    // MARK: - Pump clock skew

    /// The host's schedule changes at 14:00 on the phone's clock; the pump's, `minutes` later on its own.
    private func skewPumpClock(_ manager: TandemPumpManager, minutes: Double) {
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(.minutes(minutes))
    }

    /// Phone 13:55, host at 1.0 U/hr; pump 14:06, at 2.0.
    private func makeSkewedManager(bluetooth: StubPumpBluetooth) -> TandemPumpManager {
        let manager = makeBaselineManager(at: .hours(14) - .minutes(5), pumpMilliunits: 2000, bluetooth: bluetooth)
        skewPumpClock(manager, minutes: 11)
        return manager
    }

    func testASkewedPumpRunsATempThatDeliversTheHostsScheduledRate() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)

        manager.fetchBasalStatus()

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [50])
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [30])
        XCTAssertEqual(manager.skewCompensationTemp?.percent, 50)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(tempBasals(delegate, queue), [], "the host keeps counting its own scheduled rate")
    }

    func testNoSkewTempWhileThePumpsRateMatchesTheHosts() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)
        skewPumpClock(manager, minutes: 11)

        manager.fetchBasalStatus()

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testNoSkewTempWithinFiveMinutes() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(2), pumpMilliunits: 2000, bluetooth: bluetooth)
        skewPumpClock(manager, minutes: 4)

        manager.fetchBasalStatus()

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testTheSkewTempIsKeptWhileItStillDeliversTheHostsRate() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.fetchBasalStatus()

        manager.clock = ManualClock(at(.hours(14) - .minutes(2)))
        manager.fetchBasalStatus()

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).count, 1)
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
    }

    func testTheSkewTempStopsOnceTheHostsSegmentCatchesUp() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.fetchBasalStatus()

        manager.clock = ManualClock(at(.hours(14) + .minutes(1)))
        manager.fetchBasalStatus()

        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).count, 1)
        XCTAssertNil(manager.skewCompensationTemp)
    }

    func testTheSkewTempStopsOnceThePumpClockIsSynced() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.fetchBasalStatus()

        skewPumpClock(manager, minutes: 0)
        manager.fetchBasalStatus()

        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertNil(manager.skewCompensationTemp)
    }

    func testAHostTempReplacesTheSkewTemp() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.fetchBasalStatus()

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [50, 75])
        XCTAssertNil(manager.skewCompensationTemp)
        XCTAssertEqual(manager.state.basalDose.value, 1.5, accuracy: 0.0001)
    }

    func testAHostCancelOnASkewedPumpLeavesASkewTemp() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: 0))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [75, 50])
        XCTAssertEqual(manager.skewCompensationTemp?.percent, 50)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    /// The host asks for the pump's own 2.0 while counting its schedule's 1.0 when no temp runs.
    func testASkewedPumpRunsARequestEqualToItsOwnRateAsAnExplicitTemp() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [100])
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 2.0, accuracy: 0.0001)
    }

    func testARequestEqualToThePumpsRateSetsNoTempWhenNotSkewed() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.0, for: .minutes(30)))

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testNoSkewTempWhileTheBasalScheduleIsUnsynced() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.state.hasSyncedBasalRateSchedule = false

        manager.fetchBasalStatus()

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testASkewedPumpClockIssuesOneAlertAndRetractsItOnceSynced() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)

        manager.reconcilePumpClockSkewAlert()
        manager.reconcilePumpClockSkewAlert()
        queue.sync {}
        delegate.waitForAlerts { !delegate.issuedAlerts.isEmpty }

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier.alertIdentifier), [TandemPumpManager.pumpClockSkewAlertIdentifier])
        XCTAssertTrue(manager.state.pumpClockSkewAlertIssued)

        skewPumpClock(manager, minutes: 0)
        manager.reconcilePumpClockSkewAlert()
        queue.sync {}
        delegate.waitForAlerts { !delegate.retractedAlerts.isEmpty }

        XCTAssertEqual(delegate.retractedAlerts.map(\.alertIdentifier), [TandemPumpManager.pumpClockSkewAlertIdentifier])
        XCTAssertFalse(manager.state.pumpClockSkewAlertIssued)
    }

    func testNoAlertWithinFiveMinutes() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)
        skewPumpClock(manager, minutes: 4)
        let (delegate, queue) = attachDelegate(manager)

        manager.reconcilePumpClockSkewAlert()
        queue.sync {}

        XCTAssertEqual(delegate.issuedAlerts.count, 0)
    }

    // MARK: - Setting the pump's clock

    private func writePumpTime(_ manager: TandemPumpManager) -> PumpManagerError? {
        let expectation = expectation(description: "writePumpTime")
        var error: PumpManagerError?
        manager.writePumpTime {
            error = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return error
    }

    private func stubPumpClock(_ bluetooth: StubPumpBluetooth, reading date: Date, writeStatus: Int = 0) {
        bluetooth.stub(TimeSinceResetRequest.self, with: TimeSinceResetResponse(
            currentTime: UInt32(Dates.fromInstantToJan12008EpochSeconds(date)),
            pumpTimeSinceReset: 1000
        ))
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: writeStatus))
    }

    /// The last sync measured 11 minutes; the pump reads 15 ahead when its clock is set.
    func testSettingThePumpsClockReportsHowFarItMoved() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        stubPumpClock(bluetooth, reading: manager.now.addingTimeInterval(.minutes(15)))
        let (delegate, queue) = attachDelegate(manager)

        XCTAssertNil(writePumpTime(manager))

        queue.sync {}
        XCTAssertEqual(delegate.clockAdjustments, [-TimeInterval.minutes(15)])
    }

    func testSettingThePumpsClockMovesTheSchedulesToThePhonesOffset() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        manager.state.basalRateSchedule.timeZone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT() + 3600)!
        stubPumpClock(bluetooth, reading: manager.now.addingTimeInterval(.hours(1)))

        XCTAssertNil(writePumpTime(manager))

        XCTAssertEqual(manager.status.timeZone, TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT()))
    }

    func testARefusedClockWriteLeavesTheSchedulesZone() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        let zone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT() + 3600)!
        manager.state.basalRateSchedule.timeZone = zone
        stubPumpClock(bluetooth, reading: manager.now.addingTimeInterval(.hours(1)), writeStatus: 1)

        XCTAssertNotNil(writePumpTime(manager))

        XCTAssertEqual(manager.status.timeZone, zone)
    }

    func testWithoutAClockReadingTheLastMeasuredOffsetIsReported() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))
        let (delegate, queue) = attachDelegate(manager)

        XCTAssertNil(writePumpTime(manager))

        queue.sync {}
        XCTAssertEqual(delegate.clockAdjustments, [-TimeInterval.minutes(11)])
    }

    func testARefusedClockWriteReportsNoAdjustment() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)
        stubPumpClock(bluetooth, reading: manager.now.addingTimeInterval(.minutes(15)), writeStatus: 1)
        let (delegate, queue) = attachDelegate(manager)

        XCTAssertNotNil(writePumpTime(manager))

        queue.sync {}
        XCTAssertEqual(delegate.clockAdjustments, [])
    }

    func testAClockAdjustmentMadeBeforeTheHostAttachesReachesItOnceItDoes() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)
        stubPumpClock(bluetooth, reading: manager.now.addingTimeInterval(.hours(1)))

        XCTAssertNil(writePumpTime(manager))
        let (delegate, queue) = attachDelegate(manager)

        queue.sync {}
        XCTAssertEqual(delegate.clockAdjustments, [-TimeInterval.hours(1)])
    }

    #if canImport(SwiftUI)
    func testASkewedPumpClockShowsAStatusHighlight() throws {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSkewedManager(bluetooth: bluetooth)

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertEqual(highlight.localizedMessage, "Pump Time Is Off")
        XCTAssertEqual(highlight.state, .warning)
    }
    #endif

    // MARK: - Temp basal duration

    private func configurationError(_ error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .configuration(underlying?) = error else { return nil }
        return underlying as? TandemPumpManagerValidationError
    }

    /// A temp runs on the pump: refused after its stop, the host would still count it.
    func testATempBasalUnderFifteenMinutesIsRefusedBeforeAnythingIsSent() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)
        bluetooth.stubBasalPump(profileMilliunits: 1000, runningTempPercent: 150)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(15) - 1)

        XCTAssertEqual(configurationError(error), .unsupportedTempBasalDuration(minutes: 14))
        XCTAssertEqual(bluetooth.sentMessages.count, 0)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
    }

    func testAZeroTempBasalUnderFifteenMinutesIsRefusedToo() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 0, for: .minutes(10))

        XCTAssertEqual(configurationError(error), .unsupportedTempBasalDuration(minutes: 10))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testATempBasalOverSeventyTwoHoursIsRefused() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .hours(72) + .minutes(1))

        XCTAssertEqual(configurationError(error), .unsupportedTempBasalDuration(minutes: 72 * 60 + 1))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testATempBasalOfANonFiniteDurationIsRefused() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)

        XCTAssertNotNil(configurationError(enactTempBasal(manager, unitsPerHour: 2.0, for: .infinity)))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testTempBasalsOfFifteenMinutesAndSeventyTwoHoursGoOut() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(15)))
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.2, for: .hours(72)))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [15, 72 * 60])
    }

    func testATempBasalIsReportedForTheWholeMinutesSentToThePump() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 1000, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30) + 40))

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.minutes), [30])
        XCTAssertEqual(tempBasals(delegate, queue).last?.endDate, at(.hours(10) + .minutes(30)))
        XCTAssertEqual(manager.state.basalDose.estimatedEndDate, at(.hours(10) + .minutes(30)))
    }

    // MARK: - The scheduled basal after a temp

    private func scheduledBasalRates(_ delegate: MockPumpManagerDelegate, _ queue: DispatchQueue) -> [Double] {
        queue.sync {}
        return delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .basal }.map(\.unitsPerHour)
    }

    /// The host's schedule reads 1.0 U/hr; the pump runs 0.8.
    func testACancelReportsTheScheduledBasalAtThePumpsProfileRate() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 800, bluetooth: bluetooth)
        let (delegate, queue) = attachDelegate(manager)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30)))

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 0, for: 0))

        XCTAssertEqual(scheduledBasalRates(delegate, queue), [0.8])
        XCTAssertEqual(manager.state.basalDose.value, 0.8, accuracy: 0.0001)
    }

    /// From 13:40 for 15 minutes, read at 14:10, after the rise to 2.0 U/hr.
    func testATempThatRanOutIsFollowedByTheScheduledBasalInForceAtItsEnd() throws {
        let bluetooth = StubPumpBluetooth()
        let manager = makeBaselineManager(at: .hours(14) - .minutes(20), pumpMilliunits: 1000, bluetooth: bluetooth)
        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(15)))

        manager.clock = ManualClock(at(.hours(14) + .minutes(10)))
        let marker = try XCTUnwrap(manager.getActivePumpEvents(endDate: manager.now).last?.dose)

        XCTAssertEqual(marker.type, .basal)
        XCTAssertEqual(marker.startDate, at(.hours(14) - .minutes(5)))
        XCTAssertEqual(marker.unitsPerHour, 1.0, accuracy: 0.0001)
    }

    /// Phone 13:58, pump 14:02.
    func testTheScheduledBasalRateInForceIsReadOnThePumpsClock() {
        let manager = makeBaselineManager(at: .hours(14) - .minutes(2), pumpMilliunits: 2000, bluetooth: StubPumpBluetooth())
        skewPumpClock(manager, minutes: 4)

        XCTAssertEqual(manager.scheduledBasalRateInForce(), 2.0, accuracy: 0.0001)
    }

    func testTheScheduledBasalRateInForceIsAReadingsProfileRate() {
        let manager = makeBaselineManager(at: .hours(10), pumpMilliunits: 800, bluetooth: StubPumpBluetooth())

        XCTAssertEqual(manager.scheduledBasalRateInForce(reading: status(profile: 800, current: 1200, bitmask: 0x02)), 0.8, accuracy: 0.0001)
        XCTAssertEqual(manager.scheduledBasalRateInForce(reading: status(profile: 800, current: 0, bitmask: 0x01)), 1.0, accuracy: 0.0001)
    }

    /// Phone 13:55, pump 14:06 at 2.0: the skew temp runs the host's 1.0.
    func testWhileThePumpClockIsSkewedTheScheduledBasalRateInForceIsTheHosts() {
        let manager = makeSkewedManager(bluetooth: StubPumpBluetooth())

        XCTAssertEqual(manager.scheduledBasalRateInForce(reading: status(profile: 2000, current: 2000, bitmask: 0)), 1.0, accuracy: 0.0001)
    }

    func testDeletingSavedPumpStateForgetsTheBasalScheduleSync() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.hasSyncedBasalRateSchedule = true
        let manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())

        manager.deleteSavedPumpState()

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }
}
