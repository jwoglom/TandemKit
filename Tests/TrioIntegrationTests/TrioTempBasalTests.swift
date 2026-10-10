import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioTempBasalTests: TrioTestCase {
    func testATempBasalAndItsCancelAreStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()

        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try trioStored("the running temp basal", until: Self.hasRunningTempBasal)
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try trioStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let temps = try assertTrioStoredWhatTheOracleExpects().stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
    }

    func testATempBasalReplacedByAnotherIsStoredByTrioAsTwo() throws {
        try pairTrio()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        let first = try trioStored("the first temp basal", until: Self.hasRunningTempBasal)
        try waitForASecondToPass(since: XCTUnwrap(first.flatMap(\.pumpEvents).last { $0.dose?.type == .tempBasal }?.date))

        try control.send(.init(command: .tempBasal, unitsPerHour: 0.5, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try trioStored("both temp basals finished") { events in
            Set(events.filter { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }.compactMap(\.dose?.unitsPerHour)) == [1.5, 0.5]
        }
        let temps = try assertTrioStoredWhatTheOracleExpects().stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5, 0.5])
        XCTAssertEqual(temps.map(\.isMutable), [false, false])
    }

    func testATempBasalAboveMaxBasalIsDroppedByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule(unitsPerHour: 1.0)
        // 250% of the profile: the most the pump runs.
        let unitsPerHour = 2.5
        XCTAssertGreaterThan(unitsPerHour, Self.maxBasal)

        try control.send(.init(command: .tempBasal, unitsPerHour: unitsPerHour, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try trioStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let (stored, oracle) = try assertTrioStoredWhatTheOracleExpects()
        XCTAssertEqual(stored.filter(\.isTempBasal), [])
        let dropped = oracle.skipped.filter { $0.event.type == .tempBasal }
        XCTAssertFalse(dropped.isEmpty)
        XCTAssertTrue(dropped.allSatisfy { $0.reason == .tempBasalAboveMaxBasal(unitsPerHour: unitsPerHour) }, "\(dropped)")
    }

    func testARelaunchOfTrioStoresTheRunningTempBasalOnceAndSyncsTrioLimitsToThePump() throws {
        try pairTrio()
        try syncBasalSchedule()
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try trioStored("the running temp basal", until: Self.hasRunningTempBasal)
        try IntegrationWait.until("Trio to have saved the driver's state with the running temp basal", timeout: 30) {
            try self.trio.savedPumpManagerState()?.basalDose.type == .tempBasal
        }

        try relaunchTrio()
        try control.send(.init(command: .sync))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))

        try trioStored("the cancelled temp basal", until: Self.hasFinishedTempBasal)
        let temps = try assertTrioStoredWhatTheOracleExpects().stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
        XCTAssertEqual(temps.map(\.isMutable), [false])
        // Trio syncs its limits to the pump whenever it sets up a pump manager, so at launch.
        try IntegrationWait.until("Trio's delivery limits on the pump", timeout: 60) {
            let limits = try self.harness.client.snapshot().limits
            return limits?.maxBasalMilliunits == Self.milliunits(Self.maxBasal) && limits?.maxBolusMilliunits == Self.milliunits(Self.maxBolus)
        }
    }

    private static func hasRunningTempBasal(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
    }

    private static func hasFinishedTempBasal(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
    }
}
