import LoopKit
#if canImport(LoopKitUI)
import LoopKitUI
#endif
@testable import TandemKit
import XCTest

/// Covers enabling and disabling Control-IQ, and the weight/TDI values that go with it.
///
/// A pump on which Control-IQ has never been configured reports a weight and TDI of zero and rejects
/// a `ChangeControlIQSettingsRequest` built from them, which is what made enabling Control-IQ from
/// the app fail until the values were set in the Tandem app (#223). These assert that such a request
/// never reaches the pump, that a pump rejection is reported with its status code, and that a weight
/// the pump reports in kilograms is converted before being sent back as pounds.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerControlIQTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func configure(
        enabled: Bool,
        weightLbs: Int,
        totalDailyInsulinUnits: Int
    ) -> Result<CGMStatusV2Response?, Error> {
        var result: Result<CGMStatusV2Response?, Error>!
        let expectation = expectation(description: "configureControlIQMode")
        manager.configureControlIQMode(ChangeControlIQSettingsRequest(
            enabled: enabled,
            weightLbs: weightLbs,
            totalDailyInsulinUnits: totalDailyInsulinUnits
        )) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private func controlIQError(_ result: Result<CGMStatusV2Response?, Error>) -> ControlIQConfigurationError? {
        guard case let .failure(error) = result else { return nil }
        return error as? ControlIQConfigurationError
    }

    private func stubAcceptedChange(status: Int = 0) {
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: status))
    }

    private func controlIQInfo(
        closedLoopEnabled: Bool = false,
        weight: Int,
        weightUnit: ControlIQInfoAbstractResponse.WeightUnit,
        totalDailyInsulin: Int
    ) -> ControlIQInfoV2Response {
        ControlIQInfoV2Response(
            closedLoopEnabled: closedLoopEnabled,
            weight: weight,
            weightUnit: weightUnit.rawValue,
            totalDailyInsulin: totalDailyInsulin,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )
    }

    // MARK: - Refusing to send unusable values

    func testEnableIsRefusedWhenWeightIsUnset() {
        stubAcceptedChange()

        let result = configure(enabled: true, weightLbs: 0, totalDailyInsulinUnits: 30)

        XCTAssertEqual(controlIQError(result), .weightNotSet)
        XCTAssertFalse(
            bluetooth.didSend(ChangeControlIQSettingsRequest.self),
            "A request the pump is known to reject must not be sent"
        )
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0, "No connection should be established for a doomed request")
    }

    func testEnableIsRefusedWhenTotalDailyInsulinIsUnset() {
        stubAcceptedChange()

        let result = configure(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 0)

        XCTAssertEqual(controlIQError(result), .totalDailyInsulinNotSet)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    func testEnableIsRefusedWhenTotalDailyInsulinIsBelowTheMinimum() {
        stubAcceptedChange()

        let result = configure(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 9)

        XCTAssertEqual(controlIQError(result), .totalDailyInsulinOutOfRange(units: 9))
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    /// Enabling Control-IQ cancels a running temp basal first, because Control-IQ takes over basal
    /// delivery. Validating up front keeps a request that cannot succeed from stopping the user's
    /// temp basal on its way to being rejected.
    func testRefusedEnableLeavesARunningTempBasalAlone() {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 1.5,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog
        )

        _ = configure(enabled: true, weightLbs: 0, totalDailyInsulinUnits: 0)

        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self), "A refused enable must not cancel the temp basal")
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    /// Turning Control-IQ off carries the same fields but does not depend on them, so it must work on
    /// a pump that has never had a weight configured.
    func testDisableIsAllowedWithUnsetWeightAndTotalDailyInsulin() {
        stubAcceptedChange()

        let result = configure(enabled: false, weightLbs: 0, totalDailyInsulinUnits: 0)

        guard case .success = result else {
            return XCTFail("Expected disabling to succeed, got \(result)")
        }
        XCTAssertTrue(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        XCTAssertFalse(manager.state.useControlIQ)
    }

    // MARK: - Reporting what the pump said

    func testPumpRejectionReportsItsStatusCode() {
        stubAcceptedChange(status: 3)

        let result = configure(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 30)

        XCTAssertEqual(controlIQError(result), .pumpRejected(status: 3))
        XCTAssertFalse(manager.state.useControlIQ, "A rejected change must not be recorded as applied")
    }

    func testUnansweredRequestReportsNoResponse() {
        let result = configure(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 30)

        XCTAssertEqual(controlIQError(result), .noResponse)
        XCTAssertFalse(manager.state.useControlIQ)
    }

    func testConnectFailureIsReported() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        stubAcceptedChange()

        let result = configure(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 30)

        guard case let .failure(error) = result,
              let commError = error as? PumpCommError,
              case .pumpNotConnected = commError
        else {
            return XCTFail("Expected a pumpNotConnected failure, got \(result)")
        }
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    func testAcceptedChangeRecordsTheValuesThatWereSent() {
        stubAcceptedChange()

        let result = configure(enabled: true, weightLbs: 154, totalDailyInsulinUnits: 42)

        guard case .success = result else {
            return XCTFail("Expected the change to be applied, got \(result)")
        }
        XCTAssertTrue(manager.state.useControlIQ)
        XCTAssertEqual(manager.state.controlIQWeightLbs, 154)
        XCTAssertEqual(manager.state.controlIQTotalDailyInsulin, 42)
    }

    // MARK: - Reading the pump's own values back

    /// Zeroes mean "Control-IQ was never configured here", not a weight of nothing -- storing them as
    /// values is what let them be sent straight back to the pump.
    func testUnconfiguredControlIQReadsBackAsUnset() {
        bluetooth.stub(
            ControlIQInfoV2Request.self,
            with: controlIQInfo(weight: 0, weightUnit: .pounds, totalDailyInsulin: 0)
        )
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value

        manager.fetchControlIQStatus()

        XCTAssertNil(manager.state.controlIQWeightLbs)
        XCTAssertNil(manager.state.controlIQTotalDailyInsulin)
    }

    /// The request always declares pounds, so a pump displaying kilograms has to be converted --
    /// otherwise 70 kg is echoed back as 70 lb, less than half the user's actual weight.
    func testWeightReportedInKilogramsIsStoredInPounds() {
        bluetooth.stub(
            ControlIQInfoV2Request.self,
            with: controlIQInfo(weight: 70, weightUnit: .kilograms, totalDailyInsulin: 42)
        )
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value

        manager.fetchControlIQStatus()

        XCTAssertEqual(manager.state.controlIQWeightLbs, 154)
        XCTAssertEqual(manager.state.controlIQWeightUnit, .kilograms)
        XCTAssertEqual(manager.state.controlIQTotalDailyInsulin, 42)
    }

    func testWeightReportedInPoundsIsStoredAsIs() {
        bluetooth.stub(
            ControlIQInfoV2Request.self,
            with: controlIQInfo(weight: 154, weightUnit: .pounds, totalDailyInsulin: 42)
        )
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value

        manager.fetchControlIQStatus()

        XCTAssertEqual(manager.state.controlIQWeightLbs, 154)
        XCTAssertEqual(manager.state.controlIQWeightUnit, .pounds)
    }

    /// Pumps at or below API 2.1 only answer the V1 request; asking for V2 there returns nothing and
    /// the settings screen has no values to show.
    func testControlIQDataUsesTheRequestVariantThePumpSpeaks() {
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV2_1.value

        let expectation = expectation(description: "getControlIQData")
        manager.getControlIQData { _, _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(bluetooth.didSend(ControlIQInfoV1Request.self))
        XCTAssertFalse(bluetooth.didSend(ControlIQInfoV2Request.self))
    }

    // MARK: - useControlIQ follows the pump

    private func readControlIQStatus(closedLoopEnabled: Bool) {
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV3_4.value
        bluetooth.stub(
            ControlIQInfoV2Request.self,
            with: controlIQInfo(closedLoopEnabled: closedLoopEnabled, weight: 150, weightUnit: .pounds, totalDailyInsulin: 40)
        )
        manager.fetchControlIQStatus()
    }

    func testControlIQTurnedOnAtThePumpTurnsUseControlIQOn() {
        manager.state.useControlIQ = false

        readControlIQStatus(closedLoopEnabled: true)

        XCTAssertTrue(manager.state.useControlIQ)
    }

    func testControlIQTurnedOffAtThePumpTurnsUseControlIQOff() {
        manager.state.useControlIQ = true

        readControlIQStatus(closedLoopEnabled: false)

        XCTAssertFalse(manager.state.useControlIQ)
    }

    func testControlIQTurnedOnAtThePumpRefusesTheHostsNextAutomaticDoses() {
        manager.state.settings = TandemPumpManagerSettings(maxBolus: 5.0)
        manager.state.useControlIQ = false

        readControlIQStatus(closedLoopEnabled: true)

        let bolused = expectation(description: "enactBolus")
        var bolusError: PumpManagerError?
        manager.enactBolus(units: 1.0, activationType: .automatic) {
            bolusError = $0
            bolused.fulfill()
        }
        let tempSet = expectation(description: "enactTempBasal")
        var tempError: PumpManagerError?
        manager.enactTempBasal(unitsPerHour: 1.0, for: .minutes(30)) {
            tempError = $0
            tempSet.fulfill()
        }
        wait(for: [bolused, tempSet], timeout: 5.0)

        for error in [bolusError, tempError] {
            guard case let .deviceState(underlying?) = error else {
                return XCTFail("expected a device state error, got \(String(describing: error))")
            }
            XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .controlIQModeActive)
        }
        XCTAssertFalse(bluetooth.didSend(InitiateBolusRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    // MARK: - Sleep schedules

    /// Sleep schedule writes are Mobi-only, from API 3.5. On anything else the request would go
    /// unanswered, so it is not sent and the settings screen shows the schedules read-only.
    func testSleepScheduleWriteIsNotAttemptedOnAPumpThatCannotAcceptIt() {
        manager.state.pumpState.pumpModel = .TSLIM_X2
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV3_4.value
        bluetooth.stub(SetSleepScheduleRequest.self, with: SetSleepScheduleResponse(status: 0))

        let (error, _) = setSleepSchedule(slot: 0, sleepSchedule())

        XCTAssertEqual(error as? SleepScheduleWriteError, .unsupported)
        XCTAssertFalse(bluetooth.didSend(SetSleepScheduleRequest.self))
        XCTAssertFalse(manager.supports(SetSleepScheduleRequest.self))
    }

    func testSleepScheduleWriteIsSentOnASupportedPump() {
        stubMobiHoldingSleepSchedules()

        let (error, readBack) = setSleepSchedule(slot: 1, sleepSchedule())

        XCTAssertNil(error)
        XCTAssertEqual(readBack?.schedule1, sleepSchedule())
        XCTAssertTrue(manager.supports(SetSleepScheduleRequest.self))
        let sent = bluetooth.sent(SetSleepScheduleRequest.self)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.slot, 1)
        XCTAssertEqual(sent.first?.schedule, sleepSchedule())
    }

    func testSleepScheduleWriteCarriesTheFlagTandemsAppSends() {
        stubMobiHoldingSleepSchedules()

        _ = setSleepSchedule(slot: 0, sleepSchedule())

        XCTAssertEqual(bluetooth.sent(SetSleepScheduleRequest.self).first?.flag, 3)
    }

    func testSleepScheduleThePumpAcceptsButDoesNotSaveFailsAsNotApplied() {
        stubMobiHoldingSleepSchedules()
        bluetooth.stub(SetSleepScheduleRequest.self, with: SetSleepScheduleResponse(status: 0))

        let (error, readBack) = setSleepSchedule(slot: 0, sleepSchedule())

        XCTAssertEqual(error as? SleepScheduleWriteError, .notApplied)
        XCTAssertEqual(readBack?.schedule0, allDay)
    }

    func testRefusedSleepScheduleFailsWithThePumpsStatusAndWhatItHolds() {
        stubMobiHoldingSleepSchedules()
        bluetooth.stub(SetSleepScheduleRequest.self, with: SetSleepScheduleResponse(status: 1))

        let (error, readBack) = setSleepSchedule(slot: 1, sleepSchedule())

        XCTAssertEqual(error as? SleepScheduleWriteError, .pumpRejected(status: 1))
        XCTAssertEqual(readBack?.schedule1, unused)
    }

    func testUnansweredSleepScheduleWriteFailsAsNoResponse() {
        stubMobiHoldingSleepSchedules()
        bluetooth.stub(SetSleepScheduleRequest.self) { _ in nil }

        let (error, readBack) = setSleepSchedule(slot: 1, sleepSchedule())

        XCTAssertEqual(error as? SleepScheduleWriteError, .noResponse)
        XCTAssertNil(readBack)
    }

    private let allDay = ControlIQSleepScheduleResponse.SleepSchedule(
        enabled: 1,
        activeDays: 0b111_1111,
        startTime: 0,
        endTime: 23 * 60 + 59
    )

    private let unused = ControlIQSleepScheduleResponse.SleepSchedule(
        enabled: 0,
        activeDays: 0,
        startTime: 23 * 60,
        endTime: 7 * 60
    )

    /// A Mobi that saves what it is sent with OK, and answers schedule reads with what it holds.
    private func stubMobiHoldingSleepSchedules() {
        manager.state.pumpState.pumpModel = .MOBI
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value
        var held = [allDay, unused, unused, unused]
        bluetooth.stub(SetSleepScheduleRequest.self) { message in
            let request = message as! SetSleepScheduleRequest
            held[request.slot] = request.schedule
            return SetSleepScheduleResponse(status: 0)
        }
        bluetooth.stub(ControlIQSleepScheduleRequest.self) { _ in
            ControlIQSleepScheduleResponse(schedule0: held[0], schedule1: held[1], schedule2: held[2], schedule3: held[3])
        }
    }

    private func setSleepSchedule(
        slot: Int,
        _ schedule: ControlIQSleepScheduleResponse.SleepSchedule
    ) -> (Error?, ControlIQSleepScheduleResponse?) {
        var result: (Error?, ControlIQSleepScheduleResponse?) = (nil, nil)
        let expectation = expectation(description: "setSleepSchedule")
        manager.setSleepSchedule(slot: slot, schedule: schedule) {
            result = ($0, $1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private func sleepSchedule() -> ControlIQSleepScheduleResponse.SleepSchedule {
        ControlIQSleepScheduleResponse.SleepSchedule(
            enabled: 1,
            activeDays: 0b111_1111,
            startTime: 22 * 60 + 30,
            endTime: 6 * 60
        )
    }

    func testControlIQDataUsesV2OnNewerPumps() {
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value

        let expectation = expectation(description: "getControlIQData")
        manager.getControlIQData { _, _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(bluetooth.didSend(ControlIQInfoV2Request.self))
        XCTAssertFalse(bluetooth.didSend(ControlIQInfoV1Request.self))
    }

    // MARK: - Status highlight

    // pumpStatusHighlight lives in TandemKitUI, which has no Linux build.
    #if canImport(SwiftUI)

    /// While Control-IQ is on the driver refuses every automatic bolus and temp basal, so the host
    /// app is not dosing. Without a status highlight the only trace of that is one loop failure per
    /// cycle, and a loop that fails earlier for some other reason (no glucose, say) hides it
    /// entirely.
    func testControlIQIsSurfacedAsAStatusHighlight() throws {
        manager.state.useControlIQ = true

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        let message = highlight.localizedMessage
        XCTAssertTrue(message.localizedCaseInsensitiveContains("control-iq"), "Got: \(message)")
        XCTAssertEqual(highlight.state, .warning)
    }

    func testNoStatusHighlightWhileControlIQIsOff() {
        manager.state.useControlIQ = false

        XCTAssertNil(manager.pumpStatusHighlight)
    }

    #endif
}
