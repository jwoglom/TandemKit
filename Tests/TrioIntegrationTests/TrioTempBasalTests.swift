import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioTempBasalTests: TrioTestCase {
    func testATempBasalAndItsCancelAreStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()

        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try trioStored("the running temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
        }
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        let batches = try trioStored("the cancelled temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let temps = try assertTrioStoredWhatTheOracleExpects(batches).stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
    }

    func testATempBasalAboveMaxBasalIsDroppedByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule(unitsPerHour: 1.0)
        // 250% of the profile: the most the pump runs.
        let unitsPerHour = 2.5
        let maxBasal = try trio.maxBasal()
        XCTAssertGreaterThan(unitsPerHour, maxBasal)

        try control.send(.init(command: .tempBasal, unitsPerHour: unitsPerHour, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        let batches = try trioStored("the cancelled temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let (stored, oracle) = try assertTrioStoredWhatTheOracleExpects(batches)
        XCTAssertEqual(stored.filter(\.isTempBasal), [])
        let dropped = oracle.skipped.filter { $0.event.type == .tempBasal }
        XCTAssertFalse(dropped.isEmpty)
        XCTAssertTrue(dropped.allSatisfy { $0.reason == .tempBasalAboveMaxBasal(unitsPerHour: unitsPerHour) }, "\(dropped)")
    }

    func testATempBasalRunningAcrossARelaunchOfTrioIsStoredOnce() throws {
        try pairTrio()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try trioStored("the running temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
        }
        try IntegrationWait.until("Trio to have saved the driver's state with the running temp basal", timeout: 30) {
            try self.trio.savedPumpManagerState()?.basalDose.type == .tempBasal
        }

        try relaunchTrio()
        try control.send(.init(command: .sync))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        let batches = try trioStored("the cancelled temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let temps = try assertTrioStoredWhatTheOracleExpects(batches).stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
    }
}
