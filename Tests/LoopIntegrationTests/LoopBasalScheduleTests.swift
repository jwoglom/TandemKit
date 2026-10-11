import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class LoopBasalScheduleTests: LoopTestCase {
    func testABasalProfileEditWhileATempBasalRunsEndsTheTempInLoop() throws {
        try pairLoop()
        try syncBasalSchedule(unitsPerHour: 1.0)
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try loopStored("the running temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
        }

        try syncBasalSchedule(unitsPerHour: 0.8)

        try loopStored("the temp basal ended at the profile edit") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let stored = try assertLoopStoredWhatTheOracleExpects()
        let temps = stored.doses.filter { $0.isTempBasal && !$0.isDeleted }
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
        let markers = stored.events.filter { $0.type == PumpEventType.basal.rawValue }
        XCTAssertEqual(markers.last?.value ?? -1, 0.8, accuracy: 1e-9, "\(stored.events)")
        XCTAssertEqual(try harness.client.snapshot().idpProfiles?.first?.segments.map(\.basalRate), [Self.milliunits(0.8)])
    }
}
