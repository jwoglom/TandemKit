import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class LoopSuspendTests: LoopTestCase {
    func testASuspendThatStopsATempBasalAndItsResumeAreStoredByLoopAsTheOracleExpects() throws {
        try pairLoop()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 0.5, duration: .minutes(30)))

        try control.send(.init(command: .suspend))
        try waitForASecondToPass(since: suspendDate(in: loopStored("the suspend", until: Self.hasSuspend)))
        try control.send(.init(command: .resume))

        try loopStored("the resume", until: Self.hasResume)
        try expectLoopKit688 {
            let stored = try assertLoopStoredWhatTheOracleExpects()
            let temps = stored.doses.filter { $0.isTempBasal && !$0.isDeleted }
            XCTAssertEqual(temps.map(\.programmedTempBasalRate), [0.5])
            XCTAssertEqual(temps.map(\.isMutable), [false])
            try assertOneSuspendClosedByItsResume(stored.events, stored.doses)
        }
    }

    func testASuspendAndResumeOnThePumpAreStoredByLoopAsTheOracleExpects() throws {
        try pairLoop()
        try syncBasalSchedule()
        try waitForTheDriversFirstHistoryRead()

        try harness.client.suspend(reason: "user")
        try waitForASecondToPass(since: suspendDate(in: loopStored("the pump's suspend", syncing: true, until: Self.hasSuspend)))
        try harness.client.resume()

        try loopStored("the pump's resume", syncing: true, until: Self.hasResume)
        try expectLoopKit688 {
            let stored = try assertLoopStoredWhatTheOracleExpects()
            try assertOneSuspendClosedByItsResume(stored.events, stored.doses)
        }
    }

    /// Loop counts a suspend as running until the next resume, so the resume must close it.
    private func assertOneSuspendClosedByItsResume(
        _ events: [LoopStoredPumpEvent],
        _ doses: [LoopCachedDose],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(events.filter { $0.type == PumpEventType.suspend.rawValue }.count, 1, "\(events)", file: file, line: line)
        let resumes = events.filter { $0.type == PumpEventType.resume.rawValue }
        XCTAssertEqual(resumes.count, 1, "\(events)", file: file, line: line)
        let suspends = doses.filter { $0.isSuspend && !$0.isDeleted }
        XCTAssertEqual(suspends.count, 1, "\(doses)", file: file, line: line)
        let suspend = try XCTUnwrap(suspends.first, file: file, line: line)
        let resume = try XCTUnwrap(resumes.first, file: file, line: line)
        XCTAssertFalse(suspend.isMutable, "\(suspend)", file: file, line: line)
        XCTAssertEqual(suspend.endDate.timeIntervalSince(resume.date), 0, accuracy: 1e-3, "\(suspend) \(resume)", file: file, line: line)
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
