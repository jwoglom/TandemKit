import LoopKit
@testable import TandemKit
import XCTest

/// The read-back after a write, and the comparison the sync poll makes against the rate the pump
/// says it is delivering. https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class BasalScheduleVerificationTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    private let idpId = 10

    /// Midday, so a test that walks a segment boundary stays inside one local day.
    private static let middayReference = Date(timeIntervalSinceReferenceDate: 700_000_000)

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

    /// `appliesWrites: false` models a pump that ACKs a write and leaves the profile untouched.
    @discardableResult
    private func stubProfile(_ segments: [StubIDPPump.Segment], appliesWrites: Bool = true) -> StubIDPPump {
        let pump = StubIDPPump(segments, idpId: idpId)
        pump.appliesWrites = appliesWrites
        pump.install(on: bluetooth)
        return pump
    }

    private func syncBasal(_ items: [RepeatingScheduleValue<Double>]) -> Result<BasalRateSchedule, Error> {
        var result: Result<BasalRateSchedule, Error>!
        let expectation = expectation(description: "syncBasalRateSchedule")
        manager.syncBasalRateSchedule(items: items) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private func response(index: Int, startTime: Int, basalMilliunits: Int) -> IDPSegmentResponse {
        IDPSegmentResponse(
            idpId: idpId,
            segmentIndex: index,
            profileStartTime: startTime,
            profileBasalRate: basalMilliunits,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
    }

    // MARK: - Pure comparison

    func testSegmentsCompareRegardlessOfIndexOrder() {
        let pump = BasalScheduleVerification.segments(for: [
            response(index: 0, startTime: 360, basalMilliunits: 850),
            response(index: 1, startTime: 0, basalMilliunits: 650)
        ])
        let expected = BasalScheduleVerification.segments(for: [
            RepeatingScheduleValue(startTime: 0, value: 0.65),
            RepeatingScheduleValue(startTime: 3600.0 * 6, value: 0.85)
        ])

        XCTAssertNil(BasalScheduleVerification.difference(pump: pump, expected: expected))
    }

    func testDifferenceNamesBothSides() {
        let pump = BasalScheduleVerification.segments(for: [response(index: 0, startTime: 0, basalMilliunits: 0)])
        let expected = BasalScheduleVerification.segments(for: [RepeatingScheduleValue(startTime: 0, value: 0.65)])

        let difference = BasalScheduleVerification.difference(pump: pump, expected: expected)

        XCTAssertEqual(difference, "pump has [0min=0mU/hr], expected [0min=650mU/hr]")
    }

    func testMissingSegmentIsADifference() {
        let pump = BasalScheduleVerification.segments(for: [response(index: 0, startTime: 0, basalMilliunits: 650)])
        let expected = BasalScheduleVerification.segments(for: [
            RepeatingScheduleValue(startTime: 0, value: 0.65),
            RepeatingScheduleValue(startTime: 3600.0 * 6, value: 0.85)
        ])

        XCTAssertNotNil(BasalScheduleVerification.difference(pump: pump, expected: expected))
    }

    // MARK: - Read-back after a write

    func testSyncReadsTheProfileBackAndSucceedsWhenItMatches() {
        stubProfile([.init(startTime: 0, basalRate: 0)])

        let result = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.65)])

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(manager.state.basalRateSchedule.items.map(\.value), [0.65])
    }

    func testSyncFailsWhenThePumpAcceptsAWriteButDoesNotApplyIt() {
        stubProfile([.init(startTime: 0, basalRate: 0)], appliesWrites: false)

        let result = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.65)])

        guard case .failure = result else {
            return XCTFail("Expected the unapplied write to fail the sync")
        }
        XCTAssertNotEqual(manager.state.basalRateSchedule.items.map(\.value), [0.65])
    }

    func testSyncFailsWhenTheProfileCannotBeReadBack() {
        stubProfile([.init(startTime: 0, basalRate: 0)])
        // Answer the discovery walk once, then go silent, so only the read-back is starved.
        bluetooth.enqueue(ProfileStatusRequest.self, responses: [
            ProfileStatusResponse(
                numberOfProfiles: 1,
                idpSlot0Id: idpId,
                idpSlot1Id: 0,
                idpSlot2Id: 0,
                idpSlot3Id: 0,
                idpSlot4Id: 0,
                idpSlot5Id: 0,
                activeSegmentIndex: 0
            ),
            nil
        ])
        bluetooth.stub(ProfileStatusRequest.self) { _ in nil }

        let result = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.65)])

        guard case .failure = result else {
            return XCTFail("Expected an unverifiable profile to fail the sync")
        }
    }

    // MARK: - Delivered rate on every sync

    private func basalStatus(rate: Double, type: Int) -> CurrentBasalStatusResponse {
        CurrentBasalStatusResponse(
            profileBasalRate: UInt32(BasalScheduleVerification.milliunits(rate)),
            currentBasalRate: UInt32(BasalScheduleVerification.milliunits(rate)),
            basalModifiedBitmask: type
        )
    }

    private func setSchedule(_ items: [(TimeInterval, Double)]) {
        manager.state.basalRateSchedule = BasalRateSchedule(
            dailyItems: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }
        )!
    }

    func testNoMismatchWhenTheDeliveredRateMatchesTheSchedule() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testMismatchIsRecordedFromWhenItWasFirstSeen() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.middayReference)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        manager.clock = ManualClock(Self.middayReference.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchSince, Self.middayReference)
    }

    func testMismatchClearsWhenTheRatesAgreeAgain() {
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchSince = Date(timeIntervalSinceNow: -.hours(1))

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testTempBasalIsNotAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 1.3, type: 0x02))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testSuspendIsNotAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x01))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testControlIQSuppressesTheCheck() {
        setSchedule([(0, 0.65)])
        manager.state.useControlIQ = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    /// Phone at 06:02 (schedule says 0.85), pump at 05:58 (schedule says 0.65), delivering 0.65.
    func testExpectedRateIsEvaluatedOnThePumpsClock() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.middayReference)
        manager.clock = ManualClock(startOfDay.addingTimeInterval(3600.0 * 6 + 120))
        manager.state.currentPumpTime = startOfDay.addingTimeInterval(3600.0 * 6 - 120)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    /// Without this the test above would pass whatever clock the check used.
    func testPhoneClockIsUsedWhenThePumpTimeIsUnknown() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.middayReference)
        manager.clock = ManualClock(startOfDay.addingTimeInterval(3600.0 * 6 + 120))
        manager.state.currentPumpTime = nil

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNotNil(manager.state.basalRateMismatchSince)
    }

    // MARK: - Event-driven trigger

    func testProfileEventsTriggerTheBasalRead() {
        let context = QualifyingEventContext()

        for event in [QualifyingEvent.profileChange, .activeProfileSegmentChange] {
            let fetches = QualifyingEventFetch.fetches(for: [event], context: context)
            XCTAssertTrue(fetches.contains(.basalStatus), "\(event) should trigger the basal read")
        }
    }
}
