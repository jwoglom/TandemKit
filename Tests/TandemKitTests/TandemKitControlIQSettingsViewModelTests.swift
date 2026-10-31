@testable import TandemKit
import XCTest

/// Covers the Control-IQ settings screen's save gate and its sleep schedule model.
///
/// Enabling Control-IQ needs a weight and total daily insulin the pump does not have until someone
/// supplies them, so the screen has to block saving and say which one is missing rather than let the
/// request go out and come back rejected (#223).
@available(macOS 13.0, iOS 14.0, *) final class TandemKitControlIQSettingsViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitControlIQSettingsViewModel

    // MARK: - Save gate

    func testNothingBlocksSavingWhileControlIQIsOff() {
        XCTAssertNil(ViewModel.validationMessage(enabled: false, weightLbs: nil, totalDailyInsulin: nil))
    }

    func testEnablingWithBothValuesMissingNamesBoth() throws {
        let message = try XCTUnwrap(ViewModel.validationMessage(
            enabled: true,
            weightLbs: nil,
            totalDailyInsulin: nil
        ))

        XCTAssertTrue(message.localizedCaseInsensitiveContains("weight"), "Got: \(message)")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("total daily insulin"), "Got: \(message)")
    }

    func testEnablingWithoutAWeightNamesTheWeight() throws {
        let message = try XCTUnwrap(ViewModel.validationMessage(
            enabled: true,
            weightLbs: nil,
            totalDailyInsulin: 30
        ))

        XCTAssertTrue(message.localizedCaseInsensitiveContains("weight"), "Got: \(message)")
        XCTAssertFalse(message.localizedCaseInsensitiveContains("total daily insulin"), "Got: \(message)")
    }

    func testEnablingWithoutATotalDailyInsulinNamesIt() throws {
        let message = try XCTUnwrap(ViewModel.validationMessage(
            enabled: true,
            weightLbs: 150,
            totalDailyInsulin: nil
        ))

        XCTAssertTrue(message.localizedCaseInsensitiveContains("total daily insulin"), "Got: \(message)")
    }

    func testEnablingWithATotalDailyInsulinBelowTheMinimumSaysSo() throws {
        let message = try XCTUnwrap(ViewModel.validationMessage(
            enabled: true,
            weightLbs: 150,
            totalDailyInsulin: 9
        ))

        XCTAssertTrue(
            message.contains(String(ControlIQSettingsLimits.allowedTotalDailyInsulinUnits.lowerBound)),
            "Expected the minimum to be named. Got: \(message)"
        )
    }

    func testNothingBlocksSavingWithBothValuesSet() {
        XCTAssertNil(ViewModel.validationMessage(enabled: true, weightLbs: 150, totalDailyInsulin: 30))
        XCTAssertNil(ViewModel.validationMessage(enabled: true, weightLbs: 1, totalDailyInsulin: 10))
    }

    // MARK: - Turning Control-IQ on

    /// Saving a change that turns Control-IQ on takes the check and confirmation the settings screen's
    /// Algorithm row makes; a save that leaves it on or turns it off goes straight to the pump.
    private func makeViewModel(
        controlIQOn: Bool,
        sessionState: CGMStatusV2Response.SessionState
    ) -> (viewModel: ViewModel, bluetooth: StubPumpBluetooth) {
        let bluetooth = StubPumpBluetooth()
        var state = TandemPumpManagerState(rawValue: [:])
        state.useControlIQ = controlIQOn
        state.controlIQWeightLbs = 154
        state.controlIQTotalDailyInsulin = 42
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        bluetooth.stub(CGMStatusV2Request.self, with: CGMStatusV2Response(
            sessionStateId: sessionState.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 100,
            transmitterBatteryStatusId: CGMStatusV2Response.TransmitterBatteryStatus.unavailable.rawValue,
            sessionDurationSeconds: 3600,
            sessionTimeRemainingSeconds: 3600,
            cgmSensorTypeId: CGMStatusV2Response.CGMSensorType.dexcomG7.rawValue,
            gracePeriod: false
        ))
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 0))
        return (ViewModel(pumpManager: manager), bluetooth)
    }

    private func drainMainQueue(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testTurningControlIQOnWithoutASensorSessionAsksForACGMAndSendsNothing() {
        let (viewModel, bluetooth) = makeViewModel(controlIQOn: false, sessionState: .stopped)
        viewModel.controlIQEnabled = true

        viewModel.saveControlIQSettings()
        drainMainQueue(until: { viewModel.enablePrompt != nil })

        XCTAssertEqual(viewModel.enablePrompt, .cgmRequired)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    func testTurningControlIQOnIsCheckedWhateverElseChangedWithIt() {
        let (viewModel, bluetooth) = makeViewModel(controlIQOn: false, sessionState: .stopped)
        viewModel.controlIQEnabled = true
        viewModel.weightLbs = 160
        viewModel.totalDailyInsulin = 45

        viewModel.saveControlIQSettings()
        drainMainQueue(until: { viewModel.enablePrompt != nil })

        XCTAssertEqual(viewModel.enablePrompt, .cgmRequired)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))
    }

    func testTurningControlIQOnWithASensorSessionSendsOnlyOnceConfirmed() {
        let (viewModel, bluetooth) = makeViewModel(controlIQOn: false, sessionState: .active)
        viewModel.controlIQEnabled = true

        viewModel.saveControlIQSettings()
        drainMainQueue(until: { viewModel.enablePrompt != nil })

        XCTAssertEqual(viewModel.enablePrompt, .confirm)
        XCTAssertFalse(bluetooth.didSend(ChangeControlIQSettingsRequest.self))

        viewModel.confirmEnablingControlIQ()
        drainMainQueue(until: { !viewModel.isLoading })

        XCTAssertEqual(bluetooth.sent(ChangeControlIQSettingsRequest.self).map(\.enabled), [true])
    }

    func testChangingTheValuesOfControlIQThatIsAlreadyOnSavesWithoutAsking() {
        let (viewModel, bluetooth) = makeViewModel(controlIQOn: true, sessionState: .stopped)
        viewModel.weightLbs = 160

        viewModel.saveControlIQSettings()
        drainMainQueue(until: { !viewModel.isLoading })

        XCTAssertNil(viewModel.enablePrompt)
        XCTAssertEqual(bluetooth.sent(ChangeControlIQSettingsRequest.self).map(\.enabled), [true])
    }

    func testTurningControlIQOffSavesWithoutAsking() {
        let (viewModel, bluetooth) = makeViewModel(controlIQOn: true, sessionState: .stopped)
        viewModel.controlIQEnabled = false

        viewModel.saveControlIQSettings()
        drainMainQueue(until: { !viewModel.isLoading })

        XCTAssertNil(viewModel.enablePrompt)
        XCTAssertEqual(bluetooth.sent(ChangeControlIQSettingsRequest.self).map(\.enabled), [false])
    }

    // MARK: - Sleep schedule slots

    /// Every slot was built without an index before, so all four shared `id: 0` and were not
    /// distinguishable as `Identifiable`.
    func testSlotsTakeTheirIdentityFromTheirIndex() {
        let response = ControlIQSleepScheduleResponse(
            schedule0: schedule(startTime: 0),
            schedule1: schedule(startTime: 60),
            schedule2: schedule(startTime: 120),
            schedule3: schedule(startTime: 180)
        )

        let slots = [response.schedule0, response.schedule1, response.schedule2, response.schedule3]
            .enumerated()
            .map { SleepScheduleSlot(from: $0.element, index: $0.offset) }

        XCTAssertEqual(slots.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(Set(slots.map(\.id)).count, 4)
    }

    func testActiveDaysRoundTripThroughTheBitmask() {
        var slot = SleepScheduleSlot(id: 0)

        slot.setActive(day: 0, true) // Monday
        slot.setActive(day: 6, true) // Sunday
        XCTAssertEqual(slot.activeDays, 0b100_0001)
        XCTAssertTrue(slot.isActive(day: 0))
        XCTAssertTrue(slot.isActive(day: 6))
        XCTAssertFalse(slot.isActive(day: 3))

        slot.setActive(day: 0, false)
        XCTAssertEqual(slot.activeDays, 0b100_0000)
        XCTAssertFalse(slot.isActive(day: 0))
    }

    func testDaysAreInThePumpsOrderMondayFirst() {
        var slot = SleepScheduleSlot(id: 0)
        slot.setActive(day: 0, true)
        slot.setActive(day: 6, true)

        XCTAssertEqual(MultiDay.fromBitmask(slot.activeDays), [.monday, .sunday])
        XCTAssertEqual(SleepScheduleSlot.dayLetters.count, 7)
        XCTAssertEqual(SleepScheduleSlot.dayLetters[0], Calendar.current.veryShortWeekdaySymbols[1])
        XCTAssertEqual(SleepScheduleSlot.dayLetters[6], Calendar.current.veryShortWeekdaySymbols[0])
    }

    func testEditsSurviveTheRoundTripToTheWireFormat() {
        var slot = SleepScheduleSlot(id: 2)
        slot.enabled = true
        slot.setActive(day: 1, true)
        slot.startTime = 22 * 60 + 30
        slot.endTime = 6 * 60

        let rebuilt = SleepScheduleSlot(from: slot.toProtocol(), index: 2)

        XCTAssertEqual(rebuilt, slot)
        XCTAssertEqual(rebuilt.startTimeText, "22:30")
        XCTAssertEqual(rebuilt.endTimeText, "6:00")
    }

    private func schedule(startTime: Int) -> ControlIQSleepScheduleResponse.SleepSchedule {
        ControlIQSleepScheduleResponse.SleepSchedule(
            enabled: 1,
            activeDays: 0,
            startTime: startTime,
            endTime: startTime + 60
        )
    }
}
