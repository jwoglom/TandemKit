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
        let suspended = try trioStored("the suspend") { events in
            events.contains { $0.type == .suspend }
        }
        let suspendDate = try XCTUnwrap(suspended.flatMap(\.pumpEvents).last { $0.type == .suspend }?.date)
        // Trio stores a row dated ahead of its clock at its clock, which would pull the driver's
        // resume, dated a second after a suspend in the same second, back into that second.
        try IntegrationWait.until("a second to pass since the suspend", timeout: 10) {
            Date() >= suspendDate.addingTimeInterval(1)
        }
        try control.send(.init(command: .resume))

        let batches = try trioStored("the resume") { events in
            events.contains { $0.type == .resume }
        }
        let stored = try assertTrioStoredWhatTheOracleExpects(batches).stored
        let temps = stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [0.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
        let suspend = try XCTUnwrap(stored.first { $0.type == TrioDoseStoreOracle.EventType.pumpSuspend.rawValue })
        let resume = try XCTUnwrap(stored.first { $0.type == TrioDoseStoreOracle.EventType.pumpResume.rawValue })
        XCTAssertGreaterThanOrEqual(resume.timestamp.timeIntervalSince(suspend.timestamp), 1, "Trio's IOB throws on a suspend and resume in one second")
    }
}
