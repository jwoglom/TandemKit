import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerOnboardingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    private let idpId = 10

    /// Differs from the all-`audioHigh` pump in `pumpGlobals` on every sound.
    private let chosenSounds = TandemPumpManagerState.PumpSounds(
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
        sounds: TandemPumpManagerState.PumpSounds? = nil
    ) -> TandemPumpManager {
        var state = TandemPumpManagerState(
            basalRateSchedule: basalRateSchedule,
            maxBasalRateUnitsPerHour: maxBasalRateUnitsPerHour,
            maxBolusUnits: maxBolusUnits
        )
        state.onboardingSounds = sounds
        return TandemPumpManager(state: state, bluetooth: bluetooth)
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

    private func soundsChanged(by request: SetPumpSoundsRequest) -> TandemPumpManagerState.PumpSounds {
        let changed = request.changeBitmask
        return TandemPumpManagerState.PumpSounds(
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
        XCTAssertNil(manager.state.onboardingSounds)
    }

    func testWritesOnlyTheSoundsThatWereChosen() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let chosen = TandemPumpManagerState.PumpSounds(general: .vibrate, alarm: .audioLow)
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosen)

        XCTAssertNil(applyOnboardingSettings(manager))

        let request = try XCTUnwrap(bluetooth.sent(SetPumpSoundsRequest.self).first)
        XCTAssertEqual(request.changeBitmask, [.generalAnnun, .alarmAnnun])
        XCTAssertEqual(soundsChanged(by: request), chosen)
    }

    func testWritesNoSoundsWhenNoneWereChosen() {
        for sounds in [nil, TandemPumpManagerState.PumpSounds()] {
            bluetooth.resetRecordedTraffic()
            stubPump(segments: [.init(startTime: 0, basalRate: 0)])
            let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: sounds)
            // Sounds in the pump-globals mirror are not choices.
            manager.state.generalAnnun = .vibrate
            manager.state.alarmAnnun = .vibrate

            XCTAssertNil(applyOnboardingSettings(manager))

            XCTAssertFalse(bluetooth.didSend(SetPumpSoundsRequest.self), String(describing: sounds))
            XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
        }
    }

    func testARefusedSoundWriteDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testAnUnansweredSoundWriteDoesNotFailSetup() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetPumpSoundsRequest.self) { _ in nil }
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5, sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    func testTryingSetupAgainResendsSoundsOnlyUntilThePumpAcceptsThem() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.enqueue(SetPumpSoundsRequest.self, responses: [SetPumpSoundsResponse(status: 1)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]), sounds: chosenSounds)

        XCTAssertNil(applyOnboardingSettings(manager))
        XCTAssertNil(applyOnboardingSettings(manager))
        XCTAssertNil(applyOnboardingSettings(manager))

        let writes = bluetooth.sent(SetPumpSoundsRequest.self)
        XCTAssertEqual(writes.map { soundsChanged(by: $0) }, [chosenSounds, chosenSounds])
    }

    func testChosenSoundsSurviveAPumpGlobalsReadBeforeTheyAreWritten() throws {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(PumpGlobalsRequest.self, with: pumpGlobals)
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
    }
}
