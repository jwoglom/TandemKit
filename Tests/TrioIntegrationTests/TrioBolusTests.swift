import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioBolusTests: TrioTestCase {
    func testAnAppBolusIsStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 1.0))

        try trioStored("a finalized bolus", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.isSMB, false)
    }

    func testAnAutomaticBolusIsStoredByTrioAsAnSMB() throws {
        try pairTrio()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 0.5, automatic: true))

        try trioStored("a finalized automatic bolus", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.map(\.isSMB), [true])
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 0.5, accuracy: 1e-9)
    }

    func testABolusCancelledPartWayIsStoredByTrioAtWhatThePumpDelivered() throws {
        try pairTrio()
        try control.send(.init(command: .bolus, units: 2.0))
        try IntegrationWait.until("the pump to have delivered part of the bolus", timeout: 60) {
            try self.harness.client.snapshot().bolus.unitsDelivered >= 0.3
        }

        try control.send(.init(command: .cancelBolus))

        try trioStored("the cancelled bolus", until: Self.hasFinalizedBolus)
        let delivered = try XCTUnwrap(harness.client.snapshot().lastBolus?.deliveredUnits)
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertLessThan(delivered, 2.0)
        XCTAssertEqual(boluses.first?.bolusAmount ?? -1, delivered, accuracy: Self.bolusIncrement)
    }

    func testABolusRunningAcrossARelaunchOfTrioIsStoredOnceFinished() throws {
        try pairTrio()
        try control.send(.init(command: .bolus, units: 2.0))
        try trioStored("the running bolus") { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == true }
        }
        try IntegrationWait.until("Trio to have saved the driver's state with the running bolus", timeout: 30) {
            try self.trio.savedPumpManagerState()?.bolusDose != nil
        }

        try relaunchTrio()

        try trioStored("the bolus finished after the relaunch", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 2.0, accuracy: 1e-9)
    }

    func testABolusThroughALinkDropIsStoredByTrioOnceFinished() throws {
        try pairTrio()
        try harness.client.setState(["bolus_rate_units_per_second": 0.1])
        try control.send(.init(command: .bolus, units: 1.0))
        try trioStored("the running bolus") { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == true }
        }

        try harness.control.disconnectPump()

        try trioStored("the bolus finished after the link came back", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 1.0, accuracy: 1e-9)
    }

    func testABolusProgrammedOnThePumpIsStoredByTrioOnceFinished() throws {
        try pairTrio()
        try control.send(.init(command: .setFeatureFlag, featureFlag: TandemFeatureFlags.Flag.historyDoseReporting.rawValue, enabled: true))
        try waitForTheDriversFirstHistoryRead()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try harness.client.startBolus(units: 1.0, source: "pump")

        try trioStored("the pump's bolus", syncing: true) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false && $0.dose?.wasProgrammedByPumpUI == true }
        }
        let boluses = try assertTrioStoredWhatTheOracleExpects().stored.filter { $0.eventType == .bolus }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.isSMB, false)
    }

    private static func hasFinalizedBolus(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
    }
}
