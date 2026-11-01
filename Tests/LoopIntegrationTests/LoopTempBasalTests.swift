import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class LoopTempBasalTests: LoopTestCase {
    func testATempBasalAndItsCancelAreStoredByLoopAsTheOracleExpects() throws {
        try pairLoop()
        try syncBasalSchedule()

        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try loopStored("the running temp basal", until: Self.hasRunningTempBasal)
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try loopStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let temps = try liveTempBasals(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
    }

    func testATempBasalReplacedByAnotherIsStoredByLoopAsTwo() throws {
        try pairLoop()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try loopStored("the first temp basal", until: Self.hasRunningTempBasal)

        try control.send(.init(command: .tempBasal, unitsPerHour: 0.5, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try loopStored("both temp basals finished") { events in
            Set(events.filter { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }.compactMap(\.dose?.unitsPerHour)) == [1.5, 0.5]
        }
        let temps = try liveTempBasals(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5, 0.5])
        XCTAssertEqual(temps.map(\.isMutable), [false, false])
    }

    /// `TrioTempBasalTests`' twin: the pump's clock an hour ahead, set back by Sync Time while a
    /// temp basal runs.
    func testATempBasalRunningAsThePumpsClockIsSetBackIsStoredInOrder() throws {
        try pairLoop()
        try syncBasalSchedule()
        try harness.client.setPumpTimeOnThePump(deltaSeconds: .hours(1))
        try control.send(.init(command: .sync))
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try loopStored("the first temp basal", until: Self.hasRunningTempBasal)

        try control.send(.init(command: .syncPumpTime))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0.5, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try loopStored("both temp basals finished") { events in
            Set(events.filter { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }.compactMap(\.dose?.unitsPerHour)) == [1.5, 0.5]
        }
        let temps = try liveTempBasals(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5, 0.5])
        XCTAssertTrue(temps.allSatisfy { $0.endDate >= $0.startDate }, "\(temps)")
    }

    /// Trio drops a reported temp basal above its max basal; Loop counts what the pump ran.
    func testATempBasalAboveLoopsMaxBasalIsStoredAsThePumpRanIt() throws {
        try pairLoop()
        try syncBasalSchedule(unitsPerHour: 1.0)
        // 250% of the profile: the most the pump runs.
        let unitsPerHour = 2.5
        XCTAssertGreaterThan(unitsPerHour, Self.maxBasal)

        try control.send(.init(command: .tempBasal, unitsPerHour: unitsPerHour, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try loopStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let temps = try liveTempBasals(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [unitsPerHour])
    }

    /// Loop, unlike Trio, does not sync its delivery limits to the pump when it sets up a pump manager.
    func testARelaunchOfLoopStoresTheRunningTempBasalOnce() throws {
        try pairLoop()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try loopStored("the running temp basal", until: Self.hasRunningTempBasal)
        try IntegrationWait.until("Loop to have saved the driver's state with the running temp basal", timeout: 30) {
            try self.loop.savedPumpManagerState()?.basalDose.type == .tempBasal
        }

        try relaunchLoop()
        try control.send(.init(command: .sync))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try loopStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let temps = try liveTempBasals(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
    }

    private func liveTempBasals(_ doses: [LoopCachedDose]) -> [LoopCachedDose] {
        doses.filter { $0.isTempBasal && !$0.isDeleted }
    }

    private static func hasRunningTempBasal(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
    }

    private static func hasFinishedTempBasal(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
    }
}
