import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// `applyOnboardingSettings` is the only thing that writes the user's schedule to a freshly paired
/// pump: Loop and Trio never sync it during onboarding.
/// https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerOnboardingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    private let idpId = 10

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
        maxBolusUnits: Double? = nil
    ) -> TandemPumpManager {
        TandemPumpManager(
            state: TandemPumpManagerState(
                basalRateSchedule: basalRateSchedule,
                maxBasalRateUnitsPerHour: maxBasalRateUnitsPerHour,
                maxBolusUnits: maxBolusUnits
            ),
            bluetooth: bluetooth
        )
    }

    /// Any stub can be overridden afterwards to model a rejection.
    @discardableResult
    private func stubPump(segments: [StubIDPPump.Segment]) -> StubIDPPump {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 0))
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))

        let pump = StubIDPPump(segments, idpId: idpId)
        pump.install(on: bluetooth)
        return pump
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
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5)

        XCTAssertNil(applyOnboardingSettings(manager))

        let order = bluetooth.sentMessages.map { String(describing: type(of: $0)) }
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

    /// Writing it would set the pump profile to the 0 U/hr this whole path exists to prevent.
    func testNeverWritesAnAllZeroPlaceholderSchedule() {
        stubPump(segments: [.init(startTime: 0, basalRate: 800)])
        let manager = makeManager(schedule: schedule([(0, 0)]))

        XCTAssertNotNil(applyOnboardingSettings(manager)?.basalSchedule)

        XCTAssertTrue(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self), "The time write is unaffected")
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
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBolusUnits: 9.5)

        let failure = applyOnboardingSettings(manager)

        XCTAssertNotNil(failure?.basalSchedule)
        XCTAssertNotNil(failure?.deliveryLimits)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
