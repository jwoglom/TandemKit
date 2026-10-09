import LoopKit
@testable import TandemKit
import XCTest

/// https://github.com/jwoglom/TandemKit/issues/206
@available(macOS 13.0, iOS 14.0, *) final class BasalVerificationTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    private let idpId = 10

    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

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
        // Answer ProfileStatusRequest for the first walk only, so the read-back walk gets no reply.
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

    /// Records the pump time three hours back, so a check reading `currentPumpTime` directly
    /// instead of the offset would land on the wrong segment.
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

    /// A single-segment pump whose scheduled basal follows whatever its profile holds.
    @discardableResult
    private func stubPumpDeliveringItsProfile(basalMilliunits: Int, appliesWrites: Bool = true) -> StubIDPPump {
        let pump = stubProfile([.init(startTime: 0, basalRate: basalMilliunits)], appliesWrites: appliesWrites)
        bluetooth.stub(CurrentBasalStatusRequest.self) { _ in
            let rate = UInt32(pump.segments[0].basalRate)
            return CurrentBasalStatusResponse(profileBasalRate: rate, currentBasalRate: rate, basalModifiedBitmask: 0)
        }
        return pump
    }

    private func profileWrites() -> Int {
        bluetooth.sent(ProfileStatusRequest.self).count
    }

    func testNoMismatchWhenTheDeliveredRateMatchesTheSchedule() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
        XCTAssertFalse(bluetooth.didSend(ProfileStatusRequest.self))
    }

    func testFirstMismatchIsRecorded() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.referenceDate)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchDetectedAt, Self.referenceDate)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .updating)
    }

    func testFirstMismatchWritesTheScheduleToThePump() {
        setSchedule([(0, 0.65)])
        let pump = stubPumpDeliveringItsProfile(basalMilliunits: 400)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(pump.segments.map(\.basalRate), [650])
        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testUpdateGoesOnWhileThePumpDoesNotApplyTheWrite() {
        setSchedule([(0, 0.65)])
        stubPumpDeliveringItsProfile(basalMilliunits: 400, appliesWrites: false)

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .updating)
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testUpdateGoesOnWhileThePumpRunsAnotherRateOnAMatchingProfile() {
        setSchedule([(0, 0.65)])
        let pump = stubProfile([.init(startTime: 0, basalRate: 400)])
        bluetooth.stub(CurrentBasalStatusRequest.self, with: basalStatus(rate: 0.4, type: 0))

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(pump.segments.map(\.basalRate), [650])
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .updating)
    }

    func testNoScheduleFromTheAppIsNotAMismatch() {
        setSchedule([(0, 0)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testAllZeroScheduleIsNotWrittenToThePump() {
        setSchedule([(0, 0)])
        let pump = stubPumpDeliveringItsProfile(basalMilliunits: 400)
        // An update opened before the host's schedule was cleared.
        manager.state.basalRateMismatchDetectedAt = Self.referenceDate

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(pump.segments.map(\.basalRate), [400])
        XCTAssertFalse(bluetooth.didSend(SetIDPSegmentRequest.self))
    }

    func testUpdateRetriesAreSpacedByTheRetryInterval() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        XCTAssertEqual(profileWrites(), 1)

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(.seconds(30)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        XCTAssertEqual(profileWrites(), 1)

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(TandemPumpManager.basalProfileUpdateRetryInterval))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        XCTAssertEqual(profileWrites(), 2)
    }

    func testMatchingReadingDoesNotEndAnUnverifiedUpdate() {
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchDetectedAt = Self.referenceDate

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchDetectedAt, Self.referenceDate)
    }

    func testMatchingReadingEndsTheUpdateOnceTheProfileReadsBackMatching() {
        setSchedule([(0, 0.65)])
        stubPumpDeliveringItsProfile(basalMilliunits: 650)
        manager.state.basalRateMismatchDetectedAt = Self.referenceDate

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
        XCTAssertFalse(bluetooth.didSend(SetIDPSegmentRequest.self))
    }

    func testMismatchOutlastingTheTimeoutFailsTheUpdate() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(TandemPumpManager.basalProfileUpdateTimeout))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalRateMismatchDetectedAt, Self.referenceDate)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .failed)
    }

    func testMismatchInsideTheTimeoutDoesNotFailTheUpdate() {
        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(.minutes(4)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .updating)
    }

    func testFailureNotifiesTheDelegate() {
        let delegate = MockPumpManagerDelegate()
        let delegateQueue = DispatchQueue(label: "basal-verification-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        setSchedule([(0, 0.65)])
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        delegateQueue.sync {}
        let updatesBefore = delegate.didUpdateStateCount

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        delegateQueue.sync {}

        XCTAssertEqual(delegate.didUpdateStateCount, updatesBefore + 1)
    }

    func testUnfailedMismatchLeavesTheBasalScheduleSynced() {
        setSchedule([(0, 0.65)])
        manager.state.hasSyncedBasalRateSchedule = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testFailedUpdateMarksTheBasalScheduleUnsynced() {
        setSchedule([(0, 0.65)])
        manager.state.hasSyncedBasalRateSchedule = true
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertTrue(manager.state.basalProfileUpdateFailed)
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    /// The field report: a temp basal running on a 0 U/hr profile, read on two syncs five minutes apart.
    func testTempBasalOnAZeroProfileMarksTheBasalScheduleUnsyncedOnceTheUpdateFails() {
        setSchedule([(0, 1.1)])
        manager.state.hasSyncedBasalRateSchedule = true
        manager.clock = ManualClock(Self.referenceDate)
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x02, profileRate: 0))

        manager.clock = ManualClock(Self.referenceDate.addingTimeInterval(.minutes(5)))
        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x02, profileRate: 0))

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testMismatchStillStandingAfterAVerifiedRetryMarksTheScheduleUnsyncedAgain() {
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true
        // What a retry whose write read back matching leaves.
        manager.state.hasSyncedBasalRateSchedule = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.9, type: 0))

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
        XCTAssertTrue(manager.state.basalProfileUpdateFailed)
    }

    func testMismatchReadingsAfterFailureDoNotNotifyTheDelegateAgain() {
        let delegate = MockPumpManagerDelegate()
        let delegateQueue = DispatchQueue(label: "basal-verification-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true
        manager.state.hasSyncedBasalRateSchedule = false
        let updatesBefore = delegate.didUpdateStateCount

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))
        delegateQueue.sync {}

        XCTAssertEqual(delegate.didUpdateStateCount, updatesBefore)
    }

    func testFailedUpdateEndsOnceARetryReadsBackMatching() {
        setSchedule([(0, 0.65)])
        let pump = stubPumpDeliveringItsProfile(basalMilliunits: 400)
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(pump.segments.map(\.basalRate), [650])
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testRetryAfterAFailureThatStillReadsAnotherRateKeepsTheScheduleUnsynced() {
        setSchedule([(0, 0.65)])
        let pump = stubProfile([.init(startTime: 0, basalRate: 400)])
        bluetooth.stub(CurrentBasalStatusRequest.self, with: basalStatus(rate: 0.4, type: 0))
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.4, type: 0))

        XCTAssertEqual(pump.segments.map(\.basalRate), [650])
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .failed)
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testSuccessfulSyncFromTheAppEndsAFailedUpdate() {
        stubProfile([.init(startTime: 0, basalRate: 400)])
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        guard case .success = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.65)]) else {
            return XCTFail("Expected the sync to succeed")
        }

        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
    }

    func testAMatchingProfileIsNotAdoptedAfterAFailedUpdate() {
        stubProfile([.init(startTime: 0, basalRate: 650)])
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.hours(1))
        manager.state.basalProfileUpdateFailed = true

        manager.adoptMatchingPumpProfile()

        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
        XCTAssertFalse(bluetooth.didSend(IDPSegmentRequest.self))
    }

    func testAdoptingAMatchingProfileEndsAnUpdate() {
        stubProfile([.init(startTime: 0, basalRate: 650)])
        setSchedule([(0, 0.65)])
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.minutes(1))

        manager.adoptMatchingPumpProfile()

        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
    }

    func testAProfileThatDiffersWhenAdoptingIsUpdated() {
        setSchedule([(0, 0.65)])
        let pump = stubPumpDeliveringItsProfile(basalMilliunits: 400)

        manager.adoptMatchingPumpProfile()

        XCTAssertEqual(pump.segments.map(\.basalRate), [650])
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
    }

    func testAProfileThatDiffersWhenAdoptingOutlastingTheTimeoutFailsTheUpdate() {
        setSchedule([(0, 0.65)])
        stubPumpDeliveringItsProfile(basalMilliunits: 400, appliesWrites: false)
        manager.state.basalRateMismatchDetectedAt = Date(timeIntervalSinceNow: -.minutes(10))

        manager.adoptMatchingPumpProfile()

        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .failed)
    }

    func testTempBasalIsCheckedAgainstTheProfileRate() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 1.3, type: 0x02, profileRate: 0.65))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testTempBasalOnAWrongProfileIsAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x02, profileRate: 0))

        XCTAssertNotNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testSuspendIsNotAMismatch() {
        setSchedule([(0, 0.65)])

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0x01))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testControlIQSuppressesTheCheck() {
        setSchedule([(0, 0.65)])
        manager.state.useControlIQ = true

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    /// Phone at 06:02 (schedule says 0.85), pump four minutes behind at 05:58 (says 0.65).
    func testExpectedRateIsEvaluatedOnThePumpsClock() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.referenceDate)
        setPumpClock(offsetFrom: startOfDay.addingTimeInterval(3600.0 * 6 + 120), by: -.minutes(4))

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNil(manager.state.basalRateMismatchDetectedAt)
    }

    func testPhoneClockIsUsedWhenThePumpOffsetIsUnknown() {
        setSchedule([(0, 0.65), (3600.0 * 6, 0.85)])
        let startOfDay = Calendar.current.startOfDay(for: Self.referenceDate)
        manager.clock = ManualClock(startOfDay.addingTimeInterval(3600.0 * 6 + 120))
        manager.state.currentPumpTime = nil

        manager.verifyDeliveredBasalRate(basalStatus(rate: 0.65, type: 0))

        XCTAssertNotNil(manager.state.basalRateMismatchDetectedAt)
    }

    // MARK: - Running temp on a mismatched profile

    private func runTempBasal(value: Double, percent: Int) {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: value,
            duration: .minutes(30),
            automatic: true,
            insulinType: nil,
            startDate: manager.now.addingTimeInterval(-.minutes(5)),
            tempRateId: 7,
            tempPercent: percent
        )
    }

    /// Schedule 0.65 U/hr; the pump's profile reads 0.4 and runs the temp at 200% of it.
    private func pumpRunsTempOnAWrongProfile(percent: Int) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 400,
            currentBasalRate: UInt32(400 * percent / 100),
            basalModifiedBitmask: 0x02
        ))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 7))
    }

    func testAFailedUpdateStopsARunningTemp() {
        setSchedule([(0, 0.65)])
        runTempBasal(value: 1.3, percent: 200)
        pumpRunsTempOnAWrongProfile(percent: 200)
        manager.state.basalRateMismatchDetectedAt = manager.now.addingTimeInterval(-.hours(1))

        manager.fetchBasalStatus()

        XCTAssertTrue(manager.state.basalProfileUpdateFailed)
        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testAMismatchInsideTheTimeoutLeavesTheTempRunning() {
        setSchedule([(0, 0.65)])
        runTempBasal(value: 1.3, percent: 200)
        pumpRunsTempOnAWrongProfile(percent: 200)

        manager.fetchBasalStatus()

        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testAZeroTempKeepsRunningThroughAFailedUpdate() {
        setSchedule([(0, 0.65)])
        runTempBasal(value: 0, percent: 0)
        pumpRunsTempOnAWrongProfile(percent: 0)
        manager.state.basalRateMismatchDetectedAt = manager.now.addingTimeInterval(-.hours(1))

        manager.fetchBasalStatus()

        XCTAssertTrue(manager.state.basalProfileUpdateFailed)
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    /// The update is queued behind the sync's own command job, so the reading it starts from is
    /// fully applied before the profile changes under it.
    func testUpdateStartedByASyncRunsAfterIt() {
        setSchedule([(0, 0.65)])
        stubPumpDeliveringItsProfile(basalMilliunits: 400)

        bluetooth.ensureConnected { _ in
            self.manager.fetchBasalStatus()
            XCTAssertFalse(self.bluetooth.didSend(SetIDPSegmentRequest.self))
        }

        XCTAssertTrue(bluetooth.didSend(SetIDPSegmentRequest.self))
        XCTAssertEqual(manager.state.basalProfileUpdateStatus, .none)
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
