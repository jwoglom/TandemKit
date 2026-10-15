import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerOnboardingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    private let idpId = 10

    private struct Sounds: Equatable {
        var quickBolus: PumpGlobalsResponse.AnnunciationEnum?
        var general: PumpGlobalsResponse.AnnunciationEnum?
        var reminder: PumpGlobalsResponse.AnnunciationEnum?
        var alert: PumpGlobalsResponse.AnnunciationEnum?
        var alarm: PumpGlobalsResponse.AnnunciationEnum?
    }

    /// Differs from the all-`audioHigh` pump in `pumpGlobals` on every sound.
    private let chosenSounds = Sounds(
        quickBolus: .audioMedium,
        general: .vibrate,
        reminder: .audioLow,
        alert: .vibrate,
        alarm: .audioMedium
    )

    private let pumpGlobals = PumpGlobalsResponse(
        quickBolusEnabledRaw: 0,
        quickBolusIncrementUnits: 500,
        quickBolusIncrementCarbs: 2000,
        quickBolusEntryType: 0,
        quickBolusStatus: 0,
        buttonAnnun: 0,
        quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue,
        generalAnnun: PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue,
        reminderAnnun: PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue,
        alertAnnun: PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue,
        alarmAnnun: PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue,
        fillTubingAnnun: 0
    )

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func schedule(_ items: [(TimeInterval, Double)]) -> BasalRateSchedule {
        BasalRateSchedule(dailyItems: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) })!
    }

    private func makeManager(
        schedule basalRateSchedule: BasalRateSchedule,
        maxBasalRateUnitsPerHour: Double? = nil,
        maxBolusUnits: Double? = nil,
        sounds: Sounds? = nil
    ) -> TandemPumpManager {
        var state = TandemPumpManagerState(
            basalRateSchedule: basalRateSchedule,
            maxBasalRateUnitsPerHour: maxBasalRateUnitsPerHour,
            maxBolusUnits: maxBolusUnits
        )
        if let sounds {
            state.quickBolusAnnun = sounds.quickBolus
            state.generalAnnun = sounds.general
            state.reminderAnnun = sounds.reminder
            state.alertAnnun = sounds.alert
            state.alarmAnnun = sounds.alarm
            state.pumpSoundsAwaitingWrite = true
        }
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func sounds(in state: TandemPumpManagerState) -> Sounds {
        Sounds(
            quickBolus: state.quickBolusAnnun,
            general: state.generalAnnun,
            reminder: state.reminderAnnun,
            alert: state.alertAnnun,
            alarm: state.alarmAnnun
        )
    }

    @discardableResult
    private func stubPump(segments: [StubIDPPump.Segment]) -> StubIDPPump {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 0))
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 0))
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))

        let pump = StubIDPPump(segments, idpId: idpId)
        pump.install(on: bluetooth)
        return pump
    }

    /// `pumpGlobals`, with the sounds and quick bolus button as the pump's writes since have set them.
    private func stubPumpGlobals(quickBolusEnabled: Bool = false) {
        var quickBolusEnabled = quickBolusEnabled
        bluetooth.stub(SetQuickBolusSettingsRequest.self) { request in
            quickBolusEnabled = (request as? SetQuickBolusSettingsRequest)?.enabled ?? quickBolusEnabled
            return SetQuickBolusSettingsResponse(status: 0)
        }
        bluetooth.stub(PumpGlobalsRequest.self) { [unowned self] _ in
            let written = bluetooth.sent(SetPumpSoundsRequest.self).last.map(soundsChanged(by:)) ?? Sounds()
            let sound = { (chosen: PumpGlobalsResponse.AnnunciationEnum?) in (chosen ?? .audioHigh).rawValue }
            return PumpGlobalsResponse(
                quickBolusEnabledRaw: quickBolusEnabled ? 1 : 0,
                quickBolusIncrementUnits: pumpGlobals.quickBolusIncrementUnits,
                quickBolusIncrementCarbs: pumpGlobals.quickBolusIncrementCarbs,
                quickBolusEntryType: pumpGlobals.quickBolusEntryType,
                quickBolusStatus: pumpGlobals.quickBolusStatus,
                buttonAnnun: pumpGlobals.buttonAnnun,
                quickBolusAnnun: sound(written.quickBolus),
                generalAnnun: sound(written.general),
                reminderAnnun: sound(written.reminder),
                alertAnnun: sound(written.alert),
                alarmAnnun: sound(written.alarm),
                fillTubingAnnun: pumpGlobals.fillTubingAnnun
            )
        }
    }

    private func soundsChanged(by request: SetPumpSoundsRequest) -> Sounds {
        let changed = request.changeBitmask
        return Sounds(
            quickBolus: changed.contains(.quickBolusAnnun) ? request.quickBolusAnnun : nil,
            general: changed.contains(.generalAnnun) ? request.generalAnnun : nil,
            reminder: changed.contains(.reminderAnnun) ? request.reminderAnnun : nil,
            alert: changed.contains(.alertAnnun) ? request.alertAnnun : nil,
            alarm: changed.contains(.alarmAnnun) ? request.alarmAnnun : nil
        )
    }

    private func applyOnboardingSettings(_ manager: TandemPumpManager) -> OnboardingSettingsFailure? {
        var result: OnboardingSettingsFailure?
        let expectation = expectation(description: "applyOnboardingSettings")
        manager.applyOnboardingSettings {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    // MARK: - Setup settings reach the state

    func testSetupSettingsSeedDeliveryLimitsAndMaxScheduleEntry() {
        let state = TandemPumpManagerState(
            basalRateSchedule: schedule([(0, 0.65), (3600.0 * 12, 1.1)]),
            maxBasalRateUnitsPerHour: 4.2,
            maxBolusUnits: 9.5
        )

        XCTAssertEqual(state.settings.maxTempBasalRate, 4.2)
        XCTAssertEqual(state.settings.maxBolus, 9.5)
        XCTAssertEqual(state.settings.maxBasalScheduleEntry, 1.1)
    }

    func testSetupSettingsAreOptional() {
        let state = TandemPumpManagerState(basalRateSchedule: schedule([(0, 0.65)]))

        XCTAssertNil(state.settings.maxTempBasalRate)
        XCTAssertNil(state.settings.maxBolus)
        XCTAssertEqual(state.settings.maxBasalScheduleEntry, 0.65)
    }

    // MARK: - The regression

    /// 0 U/hr is the profile the report on #206 found on a pump paired from the Tandem app.
    func testWritesSetupBasalScheduleOntoAnUnconfiguredProfile() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65), (3600.0 * 6, 0.85)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        let writes = bluetooth.sent(SetIDPSegmentRequest.self)
        XCTAssertEqual(writes.map(\.profileStartTime), [0, 360])
        XCTAssertEqual(writes.map(\.profileBasalRate), [650, 850])
    }

    func testWritesNoSegmentsWhenPumpAlreadyMatchesTheSchedule() {
        stubPump(segments: [
            .init(startTime: 0, basalRate: 650),
            .init(startTime: 360, basalRate: 850)
        ])
        let manager = makeManager(schedule: schedule([(0, 0.65), (3600.0 * 6, 0.85)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
    }

    // MARK: - Ordering and coverage of the sequence

    func testWritesDeliveryLimitsBeforeBasalSegments() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(
            schedule: schedule([(0, 0.65)]),
            maxBasalRateUnitsPerHour: 4.2,
            maxBolusUnits: 9.5
        )

        XCTAssertNil(applyOnboardingSettings(manager))

        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        let lastLimit = order.lastIndex { $0.hasPrefix("SetMax") }
        let firstSegment = order.firstIndex(of: "SetIDPSegmentRequest")
        XCTAssertNotNil(lastLimit)
        XCTAssertNotNil(firstSegment)
        XCTAssertLessThan(lastLimit ?? .max, firstSegment ?? 0)

        XCTAssertEqual(bluetooth.sent(SetMaxBasalLimitRequest.self).first?.maxHourlyBasalMilliunits, 4200)
        XCTAssertEqual(bluetooth.sent(SetMaxBolusLimitRequest.self).first?.maxBolusMilliunits, 9500)
    }

    func testSyncsPumpTimeAfterTheOtherWrites() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        XCTAssertTrue(order.contains("SetPumpSoundsRequest"))
        XCTAssertEqual(order.last, "ChangeTimeDateRequest")
    }

    func testSkipsDeliveryLimitsWhenSetupSuppliedNone() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.sent(SetMaxBasalLimitRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.sent(SetMaxBolusLimitRequest.self).isEmpty)
        XCTAssertFalse(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
    }

    // MARK: - Failures

    func testReportsErrorWhenPumpRejectsBasalSegment() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetIDPSegmentRequest.self, with: SetIDPSegmentResponse(status: 3, unknown: 0))
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        let failure = applyOnboardingSettings(manager)

        XCTAssertNotNil(failure?.basalSchedule)
        XCTAssertNil(failure?.deliveryLimits)
    }

    func testStillWritesScheduleAndTimeWhenDeliveryLimitsAreRejected() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 1))
        let manager = makeManager(
            schedule: schedule([(0, 0.65)]),
            maxBasalRateUnitsPerHour: 4.2,
            maxBolusUnits: 9.5
        )

        let failure = applyOnboardingSettings(manager)

        XCTAssertNotNil(failure?.deliveryLimits)
        XCTAssertNil(failure?.basalSchedule)
        XCTAssertEqual(bluetooth.sent(SetIDPSegmentRequest.self).first?.profileBasalRate, 650)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testReportsBothWhenLimitsAndBasalFail() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 1))
        bluetooth.stub(SetIDPSegmentRequest.self, with: SetIDPSegmentResponse(status: 3, unknown: 0))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBasalRateUnitsPerHour: 4.2)

        let failure = applyOnboardingSettings(manager)

        XCTAssertNotNil(failure?.basalSchedule)
        XCTAssertNotNil(failure?.deliveryLimits)
    }

    func testClockFailureDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5)

        XCTAssertNil(applyOnboardingSettings(manager))
    }

    func testNeverWritesAnAllZeroPlaceholderSchedule() {
        stubPump(segments: [.init(startTime: 0, basalRate: 800)])
        let manager = makeManager(schedule: schedule([(0, 0)]))

        XCTAssertNotNil(applyOnboardingSettings(manager)?.basalSchedule)

        XCTAssertTrue(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self), "The time write is unaffected")
    }

    func testScheduleOverTheSegmentLimitFailsSetupWithoutWritingSegments() {
        stubPump(segments: [.init(startTime: 0, basalRate: 800)])
        let manager = makeManager(schedule: schedule((0 ..< 17).map { (3600.0 * Double($0), 0.65) }))

        let failure = applyOnboardingSettings(manager)

        XCTAssertEqual(failure?.basalSchedule as? BasalScheduleSyncError, .tooManyEntries(count: 17, maximum: 16))
        XCTAssertTrue(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
    }

    func testWritesScheduleContainingAZeroSegment() {
        stubPump(segments: [.init(startTime: 0, basalRate: 800)])
        let manager = makeManager(schedule: schedule([(0, 0.65), (3600.0 * 2, 0)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertEqual(bluetooth.sent(SetIDPSegmentRequest.self).map(\.profileBasalRate), [650, 0])
    }

    func testReportsErrorWhenPumpIsUnreachable() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.connectError = PumpCommError.pumpNotConnected
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        let failure = applyOnboardingSettings(manager)

        XCTAssertNotNil(failure?.basalSchedule)
        XCTAssertNotNil(failure?.deliveryLimits)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Sounds

    func testWritesTheSoundsChosenDuringOnboarding() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        let writes = bluetooth.sent(SetPumpSoundsRequest.self)
        XCTAssertEqual(writes.count, 1)
        let request = try XCTUnwrap(writes.first)
        XCTAssertEqual(request.changeBitmask, [.quickBolusAnnun, .generalAnnun, .reminderAnnun, .alertAnnun, .alarmAnnun])
        XCTAssertEqual(soundsChanged(by: request), chosenSounds)
        XCTAssertEqual(sounds(in: manager.state), chosenSounds)
        XCTAssertFalse(manager.state.pumpSoundsAwaitingWrite)
    }

    func testWritesOnlyTheSoundsThatWereChosen() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let chosen = Sounds(general: .vibrate, alarm: .audioLow)
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosen)

        XCTAssertNil(applyOnboardingSettings(manager))

        let request = try XCTUnwrap(bluetooth.sent(SetPumpSoundsRequest.self).first)
        XCTAssertEqual(request.changeBitmask, [.generalAnnun, .alarmAnnun])
        XCTAssertEqual(soundsChanged(by: request), chosen)
    }

    func testWritesNoSoundsWhenTheSoundScreenSetNone() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: Sounds())

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertFalse(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
        XCTAssertFalse(manager.state.pumpSoundsAwaitingWrite)
    }

    func testSoundsReadFromThePumpAreNotWrittenBack() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]))
        manager.state.generalAnnun = .vibrate
        manager.state.alarmAnnun = .vibrate

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertFalse(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testARefusedSoundWriteDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testAfterARefusedSoundWriteThePumpsOwnSoundsAreShown() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        bluetooth.stub(PumpGlobalsRequest.self, with: pumpGlobals)
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))
        XCTAssertFalse(manager.state.pumpSoundsAwaitingWrite)
        manager.fetchGlobalPumpSettings()

        XCTAssertEqual(
            sounds(in: manager.state),
            Sounds(quickBolus: .audioHigh, general: .audioHigh, reminder: .audioHigh, alert: .audioHigh, alarm: .audioHigh)
        )
    }

    func testAnUnansweredSoundWriteDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self) { _ in nil }
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testTryingSetupAgainDoesNotResendTheSounds() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))
        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertEqual(bluetooth.sent(SetPumpSoundsRequest.self).count, 1)
    }

    func testChosenSoundsSurviveAPumpGlobalsReadBeforeTheyAreWritten() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        stubPumpGlobals()
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)
        // A .globalPumpSettings event, handled before the sound write as one deferred from pairing would be.
        bluetooth.stub(SetMaxBolusLimitRequest.self) { [weak manager] _ in
            manager?.handleQualifyingEvents(events: [.globalPumpSettings]) {}
            return SetMaxBolusLimitResponse(status: 0)
        }

        XCTAssertNil(applyOnboardingSettings(manager))

        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        let read = try XCTUnwrap(order.firstIndex(of: "PumpGlobalsRequest"))
        let write = try XCTUnwrap(order.firstIndex(of: "SetPumpSoundsRequest"))
        XCTAssertLessThan(read, write)
        let request = try XCTUnwrap(bluetooth.sent(SetPumpSoundsRequest.self).first)
        XCTAssertEqual(soundsChanged(by: request), chosenSounds)
        XCTAssertEqual(sounds(in: manager.state), chosenSounds)
    }

    // MARK: - Quick bolus button

    func testSetupTurnsOffTheQuickBolusButton() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        stubPumpGlobals(quickBolusEnabled: true)
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        let request = try XCTUnwrap(bluetooth.sent(SetQuickBolusSettingsRequest.self).first)
        XCTAssertFalse(request.enabled)
        XCTAssertEqual(manager.state.quickBolusEnabled, false)
        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
        XCTAssertEqual(order.last, "ChangeTimeDateRequest")
    }

    func testSetupSendsNothingForAQuickBolusButtonAlreadyOff() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        stubPumpGlobals(quickBolusEnabled: false)
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(PumpGlobalsRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
        XCTAssertEqual(manager.state.quickBolusEnabled, false)
    }

    func testSetupLeavesTheQuickBolusButtonAloneWithQuickBolusSupport() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        stubPumpGlobals(quickBolusEnabled: true)
        let manager = makeManager(schedule: schedule([(0, 0.65)]))
        manager.state.featureFlags[.quickBolusButtonSupport] = true

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testAnUnansweredPumpGlobalsReadDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(PumpGlobalsRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
        XCTAssertNil(manager.state.quickBolusEnabled)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testARefusedQuickBolusDisableDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        stubPumpGlobals(quickBolusEnabled: true)
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertEqual(manager.state.quickBolusEnabled, true, "the first sync tries again")
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    // MARK: - Control-IQ

    private func controlIQInfo(on: Bool) -> ControlIQInfoV2Response {
        ControlIQInfoV2Response(
            closedLoopEnabled: on,
            weight: 150,
            weightUnit: ControlIQInfoAbstractResponse.WeightUnit.pounds.rawValue,
            totalDailyInsulin: 40,
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

    private func makeManager(controlIQOn: Bool) -> TandemPumpManager {
        let manager = makeManager(schedule: schedule([(0, 0.65)]))
        manager.state.pumpState.apiVersion = KnownApiVersion.apiV3_4.value
        bluetooth.stub(ControlIQInfoV2Request.self, with: controlIQInfo(on: controlIQOn))
        return manager
    }

    /// A pump whose Control-IQ goes off once the turn-off reaches it, however that is answered.
    private func stubControlIQOffOnceTurnedOff() {
        bluetooth.stub(ControlIQInfoV2Request.self) { [unowned self] _ in
            controlIQInfo(on: !bluetooth.didSend(ChangeControlIQSettingsRequest.self))
        }
    }

    private func controlIQNeedsTurningOff(_ manager: TandemPumpManager) -> Bool {
        var result = false
        let expectation = expectation(description: "controlIQNeedsTurningOffForSetup")
        manager.controlIQNeedsTurningOffForSetup {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private func turnOffControlIQ(_ manager: TandemPumpManager) -> Error? {
        var result: Error?
        let expectation = expectation(description: "turnOffControlIQForSetup")
        manager.turnOffControlIQForSetup {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    func testSetupAsksToTurnOffControlIQThePumpIsRunning() {
        let manager = makeManager(controlIQOn: true)

        XCTAssertTrue(controlIQNeedsTurningOff(manager))

        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    func testSetupHasNothingToTurnOffWhenControlIQIsOff() {
        let manager = makeManager(controlIQOn: false)

        XCTAssertFalse(controlIQNeedsTurningOff(manager))
    }

    func testSetupAsksToTurnOffControlIQEvenWithControlIQSupport() {
        let manager = makeManager(controlIQOn: true)
        manager.state.featureFlags[.controlIQSupport] = true

        XCTAssertTrue(controlIQNeedsTurningOff(manager))
    }

    func testAnUnansweredControlIQReadAsksNothing() {
        let manager = makeManager(controlIQOn: true)
        bluetooth.stub(ControlIQInfoV2Request.self) { _ in nil }

        XCTAssertFalse(controlIQNeedsTurningOff(manager))
    }

    func testTurningControlIQOffForSetupSendsTheDisableAndSyncsNothing() throws {
        let manager = makeManager(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 0))
        XCTAssertTrue(controlIQNeedsTurningOff(manager))

        XCTAssertNil(turnOffControlIQ(manager))

        let request = try XCTUnwrap(bluetooth.sent(ChangeControlIQSettingsRequest.self).first)
        XCTAssertFalse(request.enabled)
        XCTAssertEqual(request.weightLbs, 150)
        XCTAssertEqual(request.totalDailyInsulinUnits, 40)
        XCTAssertFalse(manager.state.useControlIQ)
        XCTAssertEqual(manager.state.controlIQEnabled, false)
        XCTAssertNil(manager.state.controlIQEndedAt)
        XCTAssertFalse(bluetooth.didSend(CurrentBasalStatusRequest.self))
    }

    func testARefusedControlIQTurnOffLeavesControlIQOn() {
        let manager = makeManager(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))
        XCTAssertTrue(controlIQNeedsTurningOff(manager))

        let error = turnOffControlIQ(manager)

        XCTAssertEqual(error as? ControlIQConfigurationError, .pumpRejected(status: 1))
        XCTAssertTrue(manager.state.useControlIQ)
        XCTAssertEqual(bluetooth.sent(ControlIQInfoV2Request.self).count, 2, "read back after the refusal")
    }

    func testAnUnansweredControlIQTurnOffSaysSo() {
        let manager = makeManager(controlIQOn: true)
        XCTAssertTrue(controlIQNeedsTurningOff(manager))

        let error = turnOffControlIQ(manager)

        XCTAssertEqual(error as? ControlIQConfigurationError, .noResponse)
        XCTAssertTrue(manager.state.useControlIQ)
    }

    func testAnUnansweredTurnOffThatReadsBackOffSucceeds() {
        let manager = makeManager(controlIQOn: true)
        XCTAssertTrue(controlIQNeedsTurningOff(manager))
        stubControlIQOffOnceTurnedOff()

        XCTAssertNil(turnOffControlIQ(manager))

        XCTAssertFalse(manager.state.useControlIQ)
        XCTAssertEqual(manager.state.controlIQEnabled, false)
        XCTAssertNil(manager.state.controlIQEndedAt)
    }

    func testARefusedTurnOffOfAPumpThatReadsOffSucceeds() {
        let manager = makeManager(controlIQOn: true)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))
        XCTAssertTrue(controlIQNeedsTurningOff(manager))
        stubControlIQOffOnceTurnedOff()

        XCTAssertNil(turnOffControlIQ(manager))

        XCTAssertFalse(manager.state.useControlIQ)
        XCTAssertNil(manager.state.controlIQEndedAt)
    }

    func testATurnOffWhoseReadBackGoesUnansweredFails() {
        let manager = makeManager(controlIQOn: true)
        XCTAssertTrue(controlIQNeedsTurningOff(manager))
        bluetooth.stub(ControlIQInfoV2Request.self) { _ in nil }

        XCTAssertEqual(turnOffControlIQ(manager) as? ControlIQConfigurationError, .noResponse)
        XCTAssertTrue(manager.state.useControlIQ)
    }
}
