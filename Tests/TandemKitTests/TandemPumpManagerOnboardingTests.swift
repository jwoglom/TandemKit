import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// Covers `applyOnboardingSettings`, the driver's half of the setup-settings hand-off.
///
/// Loop and Trio never call `syncBasalRateSchedule` or `syncDeliveryLimits` during onboarding --
/// LoopKit's therapy settings editors save locally in `.acceptanceFlow` mode and the app passes
/// the values to the driver as `PumpManagerSetupSettings` instead. So nothing but this writes the
/// user's schedule to a freshly paired pump. https://github.com/jwoglom/TandemKit/issues/206
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

    /// Stubs every write the onboarding sequence makes, against one active profile holding
    /// `segments`. Any stub can be overridden afterwards to model a rejection.
    @discardableResult
    private func stubPump(segments: [StubIDPPump.Segment]) -> StubIDPPump {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 0))
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))

        let pump = StubIDPPump(segments, idpId: idpId)
        pump.install(on: bluetooth)
        return pump
    }

    private func applyOnboardingSettings(_ manager: TandemPumpManager) -> Error? {
        var result: Error?
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

    /// A pump paired straight out of the Tandem app sits on a profile the user never configured
    /// here -- 0 U/hr in the report on #206. Onboarding has to write the host's schedule onto it.
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

    /// Limits before segments: the schedule should be written against the limits the user
    /// configured, not whatever ceiling the pump was already holding.
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

    /// The pump's own limits stay in place when the host supplied none, rather than being
    /// overwritten with a zero.
    func testSkipsDeliveryLimitsWhenSetupSuppliedNone() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.sent(SetMaxBasalLimitRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.sent(SetMaxBolusLimitRequest.self).isEmpty)
        XCTAssertFalse(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
    }

    // MARK: - Failures

    /// A rejected segment write is the #206 state itself: the pump keeps a profile the app is not
    /// reporting. It has to come back as an error, not be swallowed.
    func testReportsErrorWhenPumpRejectsBasalSegment() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetIDPSegmentRequest.self, with: SetIDPSegmentResponse(status: 3, unknown: 0))
        let manager = makeManager(schedule: schedule([(0, 0.65)]))

        XCTAssertNotNil(applyOnboardingSettings(manager))
    }

    /// The writes are independent, so a failed limit must not cost the user their basal schedule.
    func testStillWritesScheduleAndTimeWhenDeliveryLimitsAreRejected() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 1))
        let manager = makeManager(
            schedule: schedule([(0, 0.65)]),
            maxBasalRateUnitsPerHour: 4.2,
            maxBolusUnits: 9.5
        )

        XCTAssertNotNil(applyOnboardingSettings(manager))

        XCTAssertEqual(bluetooth.sent(SetIDPSegmentRequest.self).first?.profileBasalRate, 650)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self))
    }

    /// The first failure is the one reported, so the error the user sees names the limit write
    /// that actually broke rather than a later one.
    func testReportsTheFirstFailureWhenSeveralWritesFail() {
        stubPump(segments: [.init(startTime: 0, basalRate: 0)])
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 1))
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 1))
        let manager = makeManager(schedule: schedule([(0, 0.65)]), maxBasalRateUnitsPerHour: 4.2)

        let error = applyOnboardingSettings(manager)

        // The limit write fails as a PumpCommError, the time write as a PumpManagerError.
        XCTAssertTrue(error is PumpCommError, "Expected the limit failure, got \(String(describing: error))")
    }

    /// The placeholder a state falls back to without a host schedule is a single 0 U/hr entry.
    /// Writing that would set the pump profile to the 0 U/hr this whole path exists to prevent.
    func testNeverWritesAnAllZeroPlaceholderSchedule() {
        stubPump(segments: [.init(startTime: 0, basalRate: 800)])
        let manager = makeManager(schedule: schedule([(0, 0)]))

        XCTAssertNotNil(applyOnboardingSettings(manager))

        XCTAssertTrue(bluetooth.sent(SetIDPSegmentRequest.self).isEmpty)
        XCTAssertTrue(bluetooth.didSend(ChangeTimeDateRequest.self), "The time write is unaffected")
    }

    /// A zero segment inside an otherwise real schedule is the user's, not a placeholder.
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

        XCTAssertNotNil(applyOnboardingSettings(manager))
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
