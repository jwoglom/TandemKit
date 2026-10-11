import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// What the host is told when the pump answers a command with a refusal.
@available(macOS 13.0, iOS 14.0, *) final class PumpRefusalTests: XCTestCase {
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

    private func makeManager(maxTempBasalRate: Double? = nil) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.settings.maxTempBasalRate = maxTempBasalRate
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func context(of error: PumpCommError?) -> String? {
        guard case let .errorResponse(context?, _, _)? = error else { return nil }
        return context
    }

    private func refusal(_ error: PumpManagerError?) -> String? {
        guard case let .deviceState(underlying?)? = error else { return nil }
        return context(of: underlying as? PumpCommError)
    }

    private func enactTempBasal(_ manager: TandemPumpManager, unitsPerHour: Double, for duration: TimeInterval = .minutes(30)) -> PumpManagerError? {
        let finished = expectation(description: "enactTempBasal")
        var result: PumpManagerError?
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        return result
    }

    private func enactBolus(_ manager: TandemPumpManager) -> PumpManagerError? {
        let finished = expectation(description: "enactBolus")
        var result: PumpManagerError?
        manager.enactBolus(units: 1.0, activationType: .manualNoRecommendation) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        return result
    }

    private func refuseSetTempRate(status: Int = 1) {
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: status, tempRateId: 0))
    }

    // MARK: - Temp basal

    func testATempBasalBelowThePumpsLowestRateIsRefusedWithTheRateItWorksOutTo() {
        bluetooth.stubBasalPump(profileMilliunits: 300)
        refuseSetTempRate()

        let error = enactTempBasal(makeManager(), unitsPerHour: 0.1)

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [33])
        XCTAssertEqual(
            refusal(error),
            "The pump refused the 33% temporary basal rate (status 1). 33% of its 0.300 U/hr basal rate is 0.099 U/hr, below the 0.100 U/hr the pump can deliver."
        )
    }

    func testATempBasalAboveTheMaximumBasalLimitIsRefusedWithThatLimit() {
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        refuseSetTempRate()

        let error = enactTempBasal(makeManager(maxTempBasalRate: 1.2), unitsPerHour: 1.5)

        XCTAssertEqual(
            refusal(error),
            "The pump refused the 150% temporary basal rate (status 1). 150% of its 1.000 U/hr basal rate is 1.500 U/hr, above the pump's maximum basal rate limit of 1.200 U/hr."
        )
    }

    func testARefusedTempBasalWithNoKnownReasonQuotesTheStatus() {
        bluetooth.stubBasalPump(profileMilliunits: 1000)
        refuseSetTempRate(status: 7)

        let error = enactTempBasal(makeManager(), unitsPerHour: 1.5)

        XCTAssertEqual(refusal(error), "The pump refused the 150% temporary basal rate (status 7).")
    }

    func testARefusedTempBasalSaysTheOneItReplacedWasAlreadyStopped() {
        bluetooth.stubBasalPump(profileMilliunits: 1000, runningTempPercent: 120)
        refuseSetTempRate()

        let error = enactTempBasal(makeManager(), unitsPerHour: 1.5)

        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(
            refusal(error),
            "The pump refused the 150% temporary basal rate (status 1). The temporary basal rate that was running had already been stopped, so the pump is back on its scheduled basal rate."
        )
    }

    func testARefusedStopOfTheRunningTempBasalSaysTheNewRateWasNotSet() {
        bluetooth.stubBasalPump(profileMilliunits: 1000, runningTempPercent: 120)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 1, tempRateId: 0))

        let error = enactTempBasal(makeManager(), unitsPerHour: 1.5)

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertEqual(
            refusal(error),
            "The pump refused to stop the temporary basal rate that is running (status 1), so the new rate was not set. The running one may still be in effect."
        )
    }

    func testARefusedCancelOfTheRunningTempBasalSaysItMayStillBeRunning() {
        bluetooth.stubBasalPump(profileMilliunits: 1000, runningTempPercent: 120)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 1, tempRateId: 0))

        let error = enactTempBasal(makeManager(), unitsPerHour: 0, for: 0)

        XCTAssertEqual(
            refusal(error),
            "The pump refused to cancel the temporary basal rate (status 1). It may still be running."
        )
    }

    // MARK: - Bolus

    private func refuseBolusPermission(status: Int = 1, nackReasonId: Int) {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: status, bolusId: 0, nackReasonId: nackReasonId))
    }

    func testABolusRefusedForThePumpsStateSaysSo() {
        refuseBolusPermission(nackReasonId: 1)

        let error = enactBolus(makeManager())

        XCTAssertEqual(
            refusal(error),
            "The pump is not in a state that allows a bolus right now, so it did not give permission for the bolus. No bolus was started."
        )
        XCTAssertFalse(bluetooth.didSend(InitiateBolusRequest.self))
    }

    func testABolusRefusedBecauseThePumpHoldsARequestSaysSo() {
        refuseBolusPermission(nackReasonId: 3)

        let error = enactBolus(makeManager())

        XCTAssertEqual(
            refusal(error),
            "The pump already has a bolus request open, possibly from another device or from the pump itself, so it did not give permission for this one. No bolus was started."
        )
    }

    func testABolusRefusedForAnUnknownReasonQuotesTheCodes() {
        refuseBolusPermission(nackReasonId: 9)

        let error = enactBolus(makeManager())

        XCTAssertEqual(
            refusal(error),
            "The pump did not give permission for the bolus (status 1, reason 9). No bolus was started."
        )
    }

    private func grantBolusPermission(bolusId: Int = 3011) {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: bolusId, nackReasonId: 0))
    }

    func testABolusWhosePermissionWasRevokedSaysSoAndReleasesIt() {
        grantBolusPermission()
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: 3011, statusTypeId: 2))

        let error = enactBolus(makeManager())

        XCTAssertEqual(
            refusal(error),
            "The pump revoked permission for the bolus before it started. No bolus was started."
        )
        XCTAssertTrue(bluetooth.didSend(BolusPermissionReleaseRequest.self))
    }

    func testABolusThePumpDoesNotStartForAnUnknownReasonQuotesTheCodes() {
        grantBolusPermission()
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 1, bolusId: 3011, statusTypeId: 0))

        let error = enactBolus(makeManager())

        XCTAssertEqual(
            refusal(error),
            "The pump did not start the bolus (status 1, type 0). No bolus was started."
        )
    }

    private func startBolus(_ manager: TandemPumpManager) {
        grantBolusPermission()
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: 3011, statusTypeId: 0))
        XCTAssertNil(enactBolus(manager))
    }

    private func cancelBolus(_ manager: TandemPumpManager) -> PumpManagerError? {
        let finished = expectation(description: "cancelBolus")
        var error: PumpManagerError?
        manager.cancelBolus { result in
            if case let .failure(failure) = result {
                error = failure
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        return error
    }

    func testARefusedCancelOfABolusSaysItMayStillBeDelivering() {
        let manager = makeManager()
        startBolus(manager)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 1, bolusId: 3011, reasonId: 0))

        let error = cancelBolus(manager)

        XCTAssertEqual(
            refusal(error),
            "The pump refused to cancel the bolus (status 1, reason 0). The bolus may still be delivering. Check the pump to see how much insulin was delivered."
        )
    }

    func testACancelOfABolusThatIsNoLongerRunningSaysSo() {
        let manager = makeManager()
        startBolus(manager)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 1, bolusId: 3011, reasonId: 2))

        let error = cancelBolus(manager)

        XCTAssertEqual(
            refusal(error),
            "The pump could not cancel the bolus because it is no longer in progress; it may have already finished. Check the pump to see how much insulin was delivered."
        )
    }

    // MARK: - Delivery limits

    private func syncLimits(_ manager: TandemPumpManager) -> Error? {
        let limits = DeliveryLimits(
            maximumBasalRate: HKQuantity(unit: HKUnit.internationalUnit().unitDivided(by: .hour()), doubleValue: 4.2),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: 9.5)
        )
        let finished = expectation(description: "syncDeliveryLimits")
        var error: Error?
        manager.syncDeliveryLimits(limits: limits) { result in
            if case let .failure(failure) = result {
                error = failure
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        return error
    }

    func testARefusedMaximumBasalLimitNamesTheLimit() {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 1))

        let error = syncLimits(makeManager())

        XCTAssertEqual(
            context(of: error as? PumpCommError),
            "The pump refused the maximum basal rate limit of 4.200 U/hr (status 1)."
        )
    }

    func testARefusedMaximumBolusLimitNamesTheLimit() {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 1))

        let error = syncLimits(makeManager())

        XCTAssertEqual(
            context(of: error as? PumpCommError),
            "The pump refused the maximum bolus limit of 9.500 U (status 1)."
        )
    }

    func testAnUnansweredLimitWriteIsNoResponseRatherThanAnInvalidPacket() {
        bluetooth.stub(SetMaxBasalLimitRequest.self) { _ in nil }

        guard case .noResponse? = syncLimits(makeManager()) as? PumpCommError else {
            return XCTFail("Expected noResponse")
        }
    }
}
