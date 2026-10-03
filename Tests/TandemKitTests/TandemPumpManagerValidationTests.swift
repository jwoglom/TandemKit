import LoopKit
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
        manager.enactBolus(units: 6.0, activationType: .manualNoRecommendation) { error in
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
        manager.enactBolus(units: 1.0, activationType: .automatic) {
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
        manager.enactTempBasal(unitsPerHour: 1.0, for: .minutes(30)) {
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
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
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

    func testTempBasalIsBlockedWhenThePumpProfileDiffersFromTheSchedule() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 900)]).install(on: bluetooth)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30))

        guard case let .configuration(underlying?) = error else {
            return XCTFail("Expected a configuration error, got \(String(describing: error))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .basalScheduleNotSynced)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
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

    func testZeroTempBasalIsRefusedWhenThePumpProfileRateIsZero() {
        let bluetooth = StubPumpBluetooth()
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0
        ))

        let error = enactTempBasal(manager, unitsPerHour: 0, for: .minutes(30))

        XCTAssertEqual(validationError(from: error), .pumpProfileBasalRateIsZero)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
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

    // MARK: - Confirmed basal rate mismatch

    func testTempBasalIsRefusedAfterAConfirmedMismatchEvenThoughThePumpProfileMatches() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 1000)]).install(on: bluetooth)
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 1400,
            currentBasalRate: 1400,
            basalModifiedBitmask: 0
        ))
        manager.state.basalRateMismatchSince = Date(timeIntervalSinceNow: -.hours(1))
        manager.verifyDeliveredBasalRate(CurrentBasalStatusResponse(
            profileBasalRate: 1400,
            currentBasalRate: 1400,
            basalModifiedBitmask: 0
        ))
        XCTAssertTrue(manager.state.basalRateMismatchConfirmed)

        let error = enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30))

        guard case let .configuration(underlying?) = error else {
            return XCTFail("Expected a configuration error, got \(String(describing: error))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .basalScheduleNotSynced)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertFalse(bluetooth.didSend(IDPSegmentRequest.self), "a matching profile is not read to re-adopt it")
    }

    func testTempBasalGoesOutAgainOnceTheMismatchClearsAndTheProfileMatches() {
        let bluetooth = StubPumpBluetooth()
        StubIDPPump([.init(startTime: 0, basalRate: 1000)]).install(on: bluetooth)
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        let matching = CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: 1000, basalModifiedBitmask: 0)
        let manager = makeUnsyncedManager(bluetooth: bluetooth)
        manager.state.basalRateMismatchSince = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalRateMismatchConfirmed = true

        manager.verifyDeliveredBasalRate(matching)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30)))
        XCTAssertTrue(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    // MARK: - Temp basal read back after it is set

    private func status(profile: UInt32, current: UInt32, bitmask: Int) -> CurrentBasalStatusResponse {
        CurrentBasalStatusResponse(profileBasalRate: profile, currentBasalRate: current, basalModifiedBitmask: bitmask)
    }

    func testReadbackMatchesTheReportedRate() {
        XCTAssertTrue(TandemPumpManager.tempBasalReadbackMatches(
            status(profile: 1100, current: 1460, bitmask: 0x02),
            reportedRate: 1.46,
            exactRate: 1.463
        ))
    }

    func testReadbackMatchesAPumpThatRoundsUpWithinOneStep() {
        XCTAssertTrue(TandemPumpManager.tempBasalReadbackMatches(
            status(profile: 1100, current: 1470, bitmask: 0x02),
            reportedRate: 1.46,
            exactRate: 1.463
        ))
    }

    /// 10% of 0.15 U/hr is 0.015, below the 0.1 U/hr floor the reported rate rounds onto.
    func testReadbackMatchesEitherSideOfTheGapBelowTheMinimumRate() {
        for current: UInt32 in [0, 15] {
            XCTAssertTrue(TandemPumpManager.tempBasalReadbackMatches(
                status(profile: 150, current: current, bitmask: 0x02),
                reportedRate: 0,
                exactRate: 0.015
            ), "\(current) mU/hr")
        }
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(
            status(profile: 150, current: 100, bitmask: 0x02),
            reportedRate: 0,
            exactRate: 0.015
        ))
    }

    func testReadbackMoreThanOneStepOffDoesNotMatch() {
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(
            status(profile: 950, current: 1263, bitmask: 0x02),
            reportedRate: 1.46,
            exactRate: 1.463
        ))
    }

    func testReadbackWithNoTempRunningDoesNotMatch() {
        XCTAssertFalse(TandemPumpManager.tempBasalReadbackMatches(
            status(profile: 1460, current: 1460, bitmask: 0),
            reportedRate: 1.46,
            exactRate: 1.46
        ))
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
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
    }

    /// Host schedule 1.0 U/hr, pump profile 0.8 before the mismatch check has confirmed it: 150% runs 1.2.
    func testMismatchedReadbackStopsTheTempBasalAndFails() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 800)
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))
        queue.sync {}

        XCTAssertEqual(validationError(from: error), .tempBasalRateMismatch(expected: 1.5, actual: 1.2))
        let sent = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        XCTAssertEqual(
            sent.filter { $0.contains("TempRate") || $0 == "CurrentBasalStatusRequest" },
            ["CurrentBasalStatusRequest", "SetTempRateRequest", "CurrentBasalStatusRequest", "StopTempRateRequest"]
        )
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(reportedTempBasalRates(delegate), [], "the host is never told the temp basal ran")
    }

    func testMismatchedTempBasalThatCannotBeStoppedIsReportedAtThePumpsRate() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stubBasalPump(profileMilliunits: 800)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 1, tempRateId: 42))
        let (manager, delegate, queue) = makeReadbackManager(bluetooth: bluetooth)

        let error = enactTempBasal(manager, unitsPerHour: 1.5, for: .minutes(30))
        queue.sync {}

        XCTAssertEqual(validationError(from: error), .tempBasalRateMismatch(expected: 1.5, actual: 1.2))
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 1.2, accuracy: 0.0001)
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

    func testDeletingSavedPumpStateForgetsTheBasalScheduleSync() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.hasSyncedBasalRateSchedule = true
        let manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())

        manager.deleteSavedPumpState()

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }
}
