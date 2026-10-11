import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioBasalScheduleTests: TrioTestCase {
    func testABasalProfileEditWhileATempBasalRunsEndsTheTempInTrio() throws {
        try pairTrio()
        try syncBasalSchedule(unitsPerHour: 1.0)
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        let running = try trioStored("the running temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
        }
        try waitForASecondToPass(since: XCTUnwrap(running.flatMap(\.pumpEvents).last { $0.dose?.type == .tempBasal }?.date))

        try syncBasalSchedule(unitsPerHour: 0.8)

        try trioStored("the temp basal ended at the profile edit") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let stored = try assertTrioStoredWhatTheOracleExpects().stored
        let temps = stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
        XCTAssertEqual(stored.last(where: \.isScheduledBasalMarker)?.tempBasalRate ?? -1, 0.8, accuracy: 1e-9, "\(stored)")
        XCTAssertEqual(try harness.client.snapshot().idpProfiles?.first?.segments.map(\.basalRate), [Self.milliunits(0.8)])
    }
}
