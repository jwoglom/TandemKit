import LoopKit
@testable import TandemKit
import XCTest

/// A `ResumePumping` whose answer was lost or refused, as `UnansweredSuspendTests` for the suspend.
@available(macOS 13.0, iOS 14.0, *) final class UnansweredResumeTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var clock: ManualClock!
    private var isSuspended = true
    private var suspendedAt: Date!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock()
        var state = TandemPumpManagerState(basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        suspendedAt = clock.now
        state.basalDose = UnfinalizedDose(suspendStartTime: suspendedAt)
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "unanswered-resume-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            self.basalStatus(suspended: self.isSuspended)
        }
        clock.advance(by: .minutes(10))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func basalStatus(suspended: Bool) -> CurrentBasalStatusResponse {
        CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: suspended ? 0 : 1000, basalModifiedBitmask: suspended ? 0x01 : 0)
    }

    /// The pump resumes, or not, and the answer never comes; the write waits out its timeout.
    private func loseTheAnswer(applying: Bool) {
        bluetooth.stub(ResumePumpingRequest.self) { [unowned self] _ in
            if applying {
                self.isSuspended = false
            }
            self.clock.advance(by: 30)
            return nil
        }
    }

    private func resume(acknowledgingAlarms: Bool = false) -> Error? {
        let done = expectation(description: "resume completion")
        var error: Error?
        let completion: (Error?) -> Void = {
            error = $0
            done.fulfill()
        }
        if acknowledgingAlarms {
            manager.resumeDeliveryAcknowledgingResumeAlarms(completion: completion)
        } else {
            manager.resumeDelivery(completion: completion)
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
        return error
    }

    private func sync() {
        let done = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
    }

    private var doses: [DoseEntry] {
        delegate.pumpEventBatches.flatMap(\.events).compactMap(\.dose)
    }

    private var resumes: [DoseEntry] {
        doses.filter { $0.type == .resume }
    }

    func testAResumeThePumpAppliedDespiteALostAnswerIsReportedAtTheSend() {
        let sentAt = clock.now
        loseTheAnswer(applying: true)

        XCTAssertNil(resume())

        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(resumes.map(\.startDate), [sentAt], "the earliest the pump could have resumed")
        XCTAssertEqual(manager.state.lastReconciliation, clock.now, "the reading after the lost answer")
        XCTAssertEqual(bluetooth.sent(ResumePumpingRequest.self).count, 1, "not sent again to a pump already delivering")
    }

    func testAResumeThePumpNeverAppliedReportsNoResume() {
        loseTheAnswer(applying: false)

        XCTAssertNotNil(resume())

        XCTAssertEqual(bluetooth.sent(CurrentBasalStatusRequest.self).count, 2, "read before the resume and back after it")
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertTrue(resumes.isEmpty)
    }

    func testARefusedResumeOnASuspendedPumpReportsNoResume() {
        bluetooth.stub(ResumePumpingRequest.self, with: ResumePumpingResponse(status: 1))

        XCTAssertNotNil(resume())

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertTrue(resumes.isEmpty)
    }

    func testARefusalFromAPumpAlreadyDeliveringSucceeds() {
        manager.state.featureFlags[.historyBackfill] = false
        isSuspended = false
        bluetooth.stub(ResumePumpingRequest.self, with: ResumePumpingResponse(status: 1))

        XCTAssertNil(resume())

        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(resumes.count, 1, "the pump's own resume, reported once at the reading before the command")
    }

    func testWithoutAReadingTheNextSyncReportsTheResume() {
        manager.state.featureFlags[.historyBackfill] = false
        let sentAt = clock.now
        loseTheAnswer(applying: true)
        bluetooth.enqueue(CurrentBasalStatusRequest.self, responses: [basalStatus(suspended: true), nil])

        XCTAssertNotNil(resume())
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertTrue(resumes.isEmpty)

        clock.advance(by: .minutes(5))
        sync()

        XCTAssertEqual(resumes.map(\.startDate), [sentAt], "at the last reading that saw the pump suspended")
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testTheSettingsResumeAcknowledgesNoAlarmWhenALostAnswerWasApplied() {
        loseTheAnswer(applying: true)

        XCTAssertNil(resume(acknowledgingAlarms: true))

        XCTAssertFalse(bluetooth.didSend(AlarmStatusRequest.self))
        XCTAssertEqual(bluetooth.sent(ResumePumpingRequest.self).count, 1)
        XCTAssertEqual(resumes.count, 1)
    }

    func testALostAnswerRightAfterTheSuspendIsDatedASecondAfterIt() {
        clock.set(suspendedAt)
        loseTheAnswer(applying: true)

        XCTAssertNil(resume())

        XCTAssertEqual(resumes.map(\.startDate), [suspendedAt.addingTimeInterval(1)], "Trio's IOB throws on a suspend and resume in one second")
    }
}
