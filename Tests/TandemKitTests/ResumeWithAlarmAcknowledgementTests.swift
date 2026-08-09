import Foundation
@testable import TandemCore
@testable import TandemKit
import XCTest

/// Covers the settings screen's "Resume Insulin Delivery" sequence: send the resume; if it fails,
/// re-read the pump's notifications and, only when a resume-pump alarm is actually active,
/// acknowledge it and reattempt once. Anything else surfaces the failure to the caller, which is
/// what puts the error sheet on screen.
final class ResumeWithAlarmAcknowledgementTests: XCTestCase {
    private enum StubError: Error, Equatable {
        case firstAttempt
        case retry
    }

    /// Records what the sequence asked the pump to do, in order, so tests can assert on the whole
    /// interaction rather than just the returned error.
    private final class PumpStub {
        /// Errors returned by successive `sendResume()` calls; nil means the pump resumed.
        private var resumeResults: [Error?]
        /// Alarms reported active by the notification state read back after a failed resume.
        private let activeAlarms: [AlarmStatusResponse.AlarmResponseType]

        private(set) var steps: [String] = []
        private(set) var acknowledgedAlarms: [AlarmStatusResponse.AlarmResponseType] = []

        init(resumeResults: [Error?], activeAlarms: [AlarmStatusResponse.AlarmResponseType] = []) {
            self.resumeResults = resumeResults
            self.activeAlarms = activeAlarms
        }

        var resumeAttempts: Int { steps.filter { $0 == "resume" }.count }
        var notificationReloads: Int { steps.filter { $0 == "reload" }.count }

        func makeSequence() -> ResumeWithAlarmAcknowledgement {
            ResumeWithAlarmAcknowledgement(
                sendResume: {
                    self.steps.append("resume")
                    guard !self.resumeResults.isEmpty else {
                        XCTFail("Sequence attempted more resumes than the test staged")
                        return nil
                    }
                    return self.resumeResults.removeFirst()
                },
                reloadNotifications: { self.steps.append("reload") },
                activeResumeAlarms: {
                    self.steps.append("readAlarms")
                    return self.activeAlarms
                },
                acknowledgeAlarm: { alarm in
                    self.steps.append("ack")
                    self.acknowledgedAlarms.append(alarm)
                }
            )
        }
    }

    // MARK: - Step 1: the resume succeeds outright

    /// The common case: nothing is inspected or acknowledged when the pump just resumes.
    func testSuccessfulResumeTouchesNothingElse() {
        let pump = PumpStub(resumeResults: [nil], activeAlarms: [.RESUME_PUMP_ALARM])

        XCTAssertNil(pump.makeSequence().run())
        XCTAssertEqual(pump.steps, ["resume"])
        XCTAssertTrue(pump.acknowledgedAlarms.isEmpty)
    }

    // MARK: - Steps 2 & 4: failure with no resume-pump alarm active

    /// A resume can fail with no resume-pump alarm involved — the pump's notifications are re-read
    /// to find that out, and then the original error is surfaced so the existing warning is shown.
    /// Nothing is acknowledged and the resume is *not* retried.
    func testFailureWithNoActiveResumeAlarmSurfacesOriginalError() {
        let pump = PumpStub(resumeResults: [StubError.firstAttempt], activeAlarms: [])

        let error = pump.makeSequence().run()

        XCTAssertEqual(error as? StubError, .firstAttempt)
        XCTAssertEqual(pump.steps, ["resume", "reload", "readAlarms"])
        XCTAssertEqual(pump.resumeAttempts, 1, "no retry without an alarm to clear")
        XCTAssertTrue(pump.acknowledgedAlarms.isEmpty)
    }

    // MARK: - Steps 3 & 5: acknowledge, then retry

    /// The whole point of the flow: the pump refuses the resume while its "insulin isn't being
    /// delivered" alarms are unacknowledged, so they are cleared and the resume reattempted — the
    /// user never sees an error.
    func testActiveResumeAlarmsAreAcknowledgedThenResumeRetried() {
        let pump = PumpStub(
            resumeResults: [StubError.firstAttempt, nil],
            activeAlarms: [.RESUME_PUMP_ALARM, .RESUME_PUMP_ALARM2]
        )

        XCTAssertNil(pump.makeSequence().run())
        XCTAssertEqual(pump.steps, ["resume", "reload", "readAlarms", "ack", "ack", "resume"])
        XCTAssertEqual(pump.acknowledgedAlarms, [.RESUME_PUMP_ALARM, .RESUME_PUMP_ALARM2])
        XCTAssertEqual(pump.resumeAttempts, 2)
    }

    /// The pump encodes the condition under two ids but does not always raise both; only the alarms
    /// actually reported active are acknowledged.
    func testOnlyActiveResumeAlarmIsAcknowledged() {
        let pump = PumpStub(resumeResults: [StubError.firstAttempt, nil], activeAlarms: [.RESUME_PUMP_ALARM2])

        XCTAssertNil(pump.makeSequence().run())
        XCTAssertEqual(pump.acknowledgedAlarms, [.RESUME_PUMP_ALARM2])
        XCTAssertEqual(pump.resumeAttempts, 2)
    }

    // MARK: - Step 6: the retry fails too

    /// When the retry fails the caller gets the retry's error (not the first attempt's) so the
    /// existing warning is still shown, and the notification state is reloaded so the list and badge
    /// do not keep showing alarms that were just acknowledged.
    func testFailedRetrySurfacesRetryErrorAndReloadsNotifications() {
        let pump = PumpStub(
            resumeResults: [StubError.firstAttempt, StubError.retry],
            activeAlarms: [.RESUME_PUMP_ALARM]
        )

        let error = pump.makeSequence().run()

        XCTAssertEqual(error as? StubError, .retry)
        XCTAssertEqual(pump.steps, ["resume", "reload", "readAlarms", "ack", "resume", "reload"])
        XCTAssertEqual(pump.notificationReloads, 2)
    }

    // MARK: - Logging

    /// Progress logging is wired through the injected closure and never affects the outcome.
    func testLogReportsAcknowledgedAlarmNames() {
        let pump = PumpStub(resumeResults: [StubError.firstAttempt, nil], activeAlarms: [.RESUME_PUMP_ALARM])
        var sequence = pump.makeSequence()
        var messages: [String] = []
        sequence.log = { messages.append($0) }

        XCTAssertNil(sequence.run())
        XCTAssertTrue(
            messages.contains { $0.contains("RESUME_PUMP_ALARM") },
            "expected the acknowledged alarm to be named in the log, got \(messages)"
        )
    }
}
