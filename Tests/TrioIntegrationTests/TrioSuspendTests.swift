import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioSuspendTests: TrioTestCase {
    func testASuspendThatStopsATempBasalAndItsResumeAreStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 0.5, duration: .minutes(30)))

        try control.send(.init(command: .suspend))
        try waitForASecondToPass(since: suspendDate(in: trioStored("the suspend", until: Self.hasSuspend)))
        try control.send(.init(command: .resume))

        try trioStored("the resume", until: Self.hasResume)
        let stored = try assertTrioStoredWhatTheOracleExpects().stored
        let temps = stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [0.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
        try assertOneSuspendThenOneResume(stored)
    }

    func testASuspendAndResumeOnThePumpAreStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()
        try waitForTheDriversFirstHistoryRead()

        try harness.client.suspend(reason: "user")
        try waitForASecondToPass(since: suspendDate(in: trioStored("the pump's suspend", syncing: true, until: Self.hasSuspend)))
        try harness.client.resume()

        try trioStored("the pump's resume", syncing: true, until: Self.hasResume)
        try assertOneSuspendThenOneResume(assertTrioStoredWhatTheOracleExpects().stored)
    }

    private func assertOneSuspendThenOneResume(_ stored: [TrioStoredPumpEvent], file: StaticString = #filePath, line: UInt = #line) throws {
        let suspends = stored.filter { $0.eventType == .pumpSuspend }
        let resumes = stored.filter { $0.eventType == .pumpResume }
        XCTAssertEqual(suspends.count, 1, "\(stored)", file: file, line: line)
        XCTAssertEqual(resumes.count, 1, "\(stored)", file: file, line: line)
        let suspend = try XCTUnwrap(suspends.first, file: file, line: line)
        let resume = try XCTUnwrap(resumes.first, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            resume.timestamp.timeIntervalSince(suspend.timestamp),
            1,
            "Trio's IOB throws on a suspend and resume in one second",
            file: file,
            line: line
        )
    }

    private func suspendDate(in batches: [VirtualPumpControl.Batch]) throws -> Date {
        try XCTUnwrap(batches.flatMap(\.pumpEvents).last { $0.type == .suspend }?.date)
    }

    private static func hasSuspend(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.type == .suspend }
    }

    private static func hasResume(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.type == .resume }
    }
}
