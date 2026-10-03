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
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0
        ))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
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
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0
        ))

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
        let matching = CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: 1000, basalModifiedBitmask: 0)
        let manager = makeSyncedManager(bluetooth: bluetooth, pumpBasal: matching)
        manager.state.hasSyncedBasalRateSchedule = false
        manager.state.basalRateMismatchSince = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalRateMismatchConfirmed = true

        manager.verifyDeliveredBasalRate(matching)

        XCTAssertNil(enactTempBasal(manager, unitsPerHour: 2.0, for: .minutes(30)))
        XCTAssertTrue(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testDeletingSavedPumpStateForgetsTheBasalScheduleSync() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.hasSyncedBasalRateSchedule = true
        let manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())

        manager.deleteSavedPumpState()

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }
}
