import LoopKit
@testable import TandemKit
import XCTest

/// https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class BasalVerificationTests: XCTestCase {
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

    @discardableResult
    private func stubProfile(_ segments: [StubIDPPump.Segment], appliesWrites: Bool = true) -> StubIDPPump {
        let pump = StubIDPPump(segments, idpId: idpId)
        pump.appliesWrites = appliesWrites
        pump.install(on: bluetooth)
        return pump
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

        guard case let .failure(error) = result,
              case let .basalProfileSyncMismatch(pump, app) = error as? PumpCommError
        else {
            return XCTFail("Expected a basalProfileSyncMismatch, got \(result)")
        }
        XCTAssertEqual(pump.map(\.profileBasalRate), [0])
        XCTAssertEqual(app.map(\.value), [0.65])
        XCTAssertNotEqual(manager.state.basalRateSchedule.items.map(\.value), [0.65])
    }

    func testMismatchErrorNamesBothSidesPerSegment() {
        let difference = PumpCommError.basalProfileDifference(
            pump: [response(index: 0, startTime: 0, basalMilliunits: 0)],
            app: [
                RepeatingScheduleValue(startTime: 0, value: 0.65),
                RepeatingScheduleValue(startTime: 3600.0 * 6, value: 0.85)
            ]
        )

        XCTAssertEqual(
            difference,
            "segment 0 pump 0min=0mU/hr vs app 0min=650mU/hr, segment 1 pump absent vs app 360min=850mU/hr"
        )
    }

    func testSyncFailsWhenThePumpKeepsASegmentTheScheduleDropped() {
        stubProfile([
            .init(startTime: 0, basalRate: 650),
            .init(startTime: 360, basalRate: 850)
        ], appliesWrites: false)

        let result = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.65)])

        guard case .failure = result else {
            return XCTFail("Expected the surplus segment to fail the sync")
        }
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

    private func basalStatus(rate: Double, type: Int, profileRate: Double? = nil) -> CurrentBasalStatusResponse {
        CurrentBasalStatusResponse(
            profileBasalRate: UInt32(((profileRate ?? rate) * 1000).rounded()),
            currentBasalRate: UInt32((rate * 1000).rounded()),
            basalModifiedBitmask: type
        )
    }

    /// Measured three hours ago, so only the offset can still be current.
    private func setPumpClock(offsetFrom phoneNow: Date, by offset: TimeInterval) {
        manager.clock = ManualClock(phoneNow)
        manager.state.lastPumpTimeCheckDate = phoneNow.addingTimeInterval(-.hours(3))
        manager.state.currentPumpTime = phoneNow.addingTimeInterval(-.hours(3) + offset)
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

    func testFirstMismatchIsRecordedButNotConfirmed() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.middayReference)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchSince, Self.middayReference)
        XCTAssertFalse(manager.state.basalRateMismatchConfirmed)
    }

    func testMismatchConfirmsOnAReadingAfterTheInterval() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.middayReference)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        manager.clock = ManualClock(Self.middayReference.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchSince, Self.middayReference)
        XCTAssertTrue(manager.state.basalRateMismatchConfirmed)
    }

    func testSecondReadingInsideTheIntervalDoesNotConfirm() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.middayReference)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        manager.clock = ManualClock(Self.middayReference.addingTimeInterval(.seconds(30)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertFalse(manager.state.basalRateMismatchConfirmed)
    }

    func testConfirmationNotifiesTheDelegate() {
        let delegate = MockPumpManagerDelegate()
        let delegateQueue = DispatchQueue(label: "basal-verification-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.middayReference)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        delegateQueue.sync {}
        let updatesBefore = delegate.didUpdateStateCount

        manager.clock = ManualClock(Self.middayReference.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        delegateQueue.sync {}

        XCTAssertEqual(delegate.didUpdateStateCount, updatesBefore + 1)
    }

    func testMismatchClearsWhenTheRatesAgreeAgain() {
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchSince = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalRateMismatchConfirmed = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
        XCTAssertFalse(manager.state.basalRateMismatchConfirmed)
    }

    func testTempBasalIsCheckedAgainstTheProfileRate() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 1.3, type: 0x02, profileRate: 0.65))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testTempBasalOnAWrongProfileIsAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x02, profileRate: 0))

        XCTAssertNotNil(manager.state.basalRateMismatchSince)
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

    /// Phone at 06:02 (schedule says 0.85), pump four minutes behind at 05:58 (says 0.65).
    func testExpectedRateIsEvaluatedOnThePumpsClock() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.middayReference)
        setPumpClock(offsetFrom: startOfDay.addingTimeInterval(3600.0 * 6 + 120), by: -.minutes(4))

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchSince)
    }

    func testPhoneClockIsUsedWhenThePumpOffsetIsUnknown() {
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
