import LoopKit
@testable import TandemKit
import XCTest

/// Covers the two checks that keep the pump's basal profile and the app's schedule from drifting
/// apart unnoticed: the read-back after a write, and the comparison the sync poll makes against
/// the rate the pump says it is delivering. https://github.com/jwoglom/TandemKit/issues/206
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

    /// One active profile holding `segments`. `appliesWrites: false` models a pump that ACKs a
    /// segment write and leaves the profile untouched.
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

    /// A status-0 response says the pump accepted the write, not that the profile holds it. If the
    /// host persisted the schedule anyway it would scale every temp basal percent off a rate the
    /// pump never adopted -- the failure in #206, just arrived at a different way.
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

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    func testFirstMismatchIsRecordedButNotYetConfirmed() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        let mismatch = manager.state.basalRateMismatch
        XCTAssertEqual(mismatch?.expectedUnitsPerHour, 0.65)
        XCTAssertEqual(mismatch?.pumpUnitsPerHour, 0)
        XCTAssertEqual(mismatch?.isConfirmed, false)
    }

    func testMismatchConfirmsOnceItOutlivesASinglePoll() {
        setSchedule([(0, 0.65)])
        let first = Date()

        var mismatch = BasalRateMismatch(
            expectedUnitsPerHour: 0.65,
            pumpUnitsPerHour: 0,
            firstSeen: first,
            lastSeen: first
        )
        XCTAssertFalse(mismatch.isConfirmed)

        mismatch = mismatch.observed(
            expectedUnitsPerHour: 0.65,
            pumpUnitsPerHour: 0,
            at: first.addingTimeInterval(.minutes(5))
        )
        XCTAssertTrue(mismatch.isConfirmed)
        XCTAssertEqual(mismatch.firstSeen, first)
    }

    /// A different pair of rates is a different fault, so the clock restarts rather than inheriting
    /// the age of the one it replaced.
    func testObservingDifferentRatesRestartsTheClock() {
        let first = Date()
        let mismatch = BasalRateMismatch(
            expectedUnitsPerHour: 0.65,
            pumpUnitsPerHour: 0,
            firstSeen: first,
            lastSeen: first
        )
        .observed(expectedUnitsPerHour: 0.65, pumpUnitsPerHour: 0.3, at: first.addingTimeInterval(.minutes(5)))

        XCTAssertEqual(mismatch.firstSeen, first.addingTimeInterval(.minutes(5)))
        XCTAssertFalse(mismatch.isConfirmed)
    }

    func testMismatchClearsWhenTheRatesAgreeAgain() {
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatch = BasalRateMismatch(
            expectedUnitsPerHour: 0.65,
            pumpUnitsPerHour: 0,
            firstSeen: Date(timeIntervalSinceNow: -.hours(1)),
            lastSeen: Date()
        )

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    /// A temp basal is supposed to deliver something other than the scheduled rate.
    func testTempBasalIsNotAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 1.3, type: 0x02))

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    func testSuspendIsNotAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x01))

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    /// Control-IQ moves basal delivery on its own, so a disagreement says nothing about the profile.
    func testControlIQSuppressesTheCheck() {
        setSchedule([(0, 0.65)])
        manager.state.useControlIQ = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    /// Phone at 06:02 (schedule says 0.85), pump at 05:58 (schedule says 0.65), pump delivering
    /// 0.65. A pump running a few minutes behind must not read as a mismatch every time a segment
    /// boundary falls between the two clocks.
    func testExpectedRateIsEvaluatedOnThePumpsClock() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.middayReference)
        manager.clock = ManualClock(startOfDay.addingTimeInterval(3600.0 * 6 + 120))
        manager.state.currentPumpTime = startOfDay.addingTimeInterval(3600.0 * 6 - 120)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatch)
    }

    /// The same reading against the phone's clock, which is what the check falls back to before a
    /// sync has read the pump's. Without it the test above would pass whatever clock was used.
    func testPhoneClockIsUsedWhenThePumpTimeIsUnknown() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.middayReference)
        manager.clock = ManualClock(startOfDay.addingTimeInterval(3600.0 * 6 + 120))
        manager.state.currentPumpTime = nil

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatch?.expectedUnitsPerHour, 0.85)
        XCTAssertEqual(manager.state.basalRateMismatch?.pumpUnitsPerHour, 0.65)
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
