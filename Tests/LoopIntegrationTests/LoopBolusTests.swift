import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class LoopBolusTests: LoopTestCase {
    func testAnAppBolusIsStoredByLoopAsTheOracleExpects() throws {
        try pairLoop()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 1.0))

        try loopStored("a finalized bolus", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.count, 1, "one bolus: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.value ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.automatic, false)
    }

    func testAnAutomaticBolusIsStoredByLoopAsAutomatic() throws {
        try pairLoop()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 0.5, automatic: true))

        try loopStored("a finalized automatic bolus", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.map(\.automatic), [true])
        XCTAssertEqual(boluses.first?.value ?? 0, 0.5, accuracy: 1e-9)
    }

    func testABolusCancelledPartWayIsStoredByLoopAtWhatThePumpDelivered() throws {
        try pairLoop()
        try harness.client.setState(["bolus_rate_units_per_second": 0.1])
        try control.send(.init(command: .bolus, units: 2.0))
        try IntegrationWait.until("the pump to have delivered part of the bolus", timeout: 60) {
            try self.harness.client.snapshot().bolus.unitsDelivered >= 0.3
        }

        try control.send(.init(command: .cancelBolus))

        try loopStored("the cancelled bolus", until: Self.hasFinalizedBolus)
        let delivered = try XCTUnwrap(harness.client.snapshot().lastBolus?.deliveredUnits)
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.count, 1, "one bolus: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertLessThan(delivered, 2.0)
        XCTAssertEqual(boluses.first?.value ?? -1, delivered, accuracy: 0.001)
    }

    func testABolusRunningAcrossARelaunchOfLoopIsStoredOnceFinished() throws {
        try pairLoop()
        try harness.client.setState(["bolus_rate_units_per_second": 0.1])
        try control.send(.init(command: .bolus, units: 2.0))
        try loopStored("the running bolus") { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == true }
        }
        try IntegrationWait.until("Loop to have saved the driver's state with the running bolus", timeout: 30) {
            try self.loop.savedPumpManagerState()?.bolusDose != nil
        }

        try relaunchLoop()

        try loopStored("the bolus finished after the relaunch", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.count, 1, "one bolus: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.value ?? 0, 2.0, accuracy: 1e-9)
    }

    func testABolusThroughALinkDropIsStoredByLoopOnceFinished() throws {
        try pairLoop()
        try harness.client.setState(["bolus_rate_units_per_second": 0.1])
        try control.send(.init(command: .bolus, units: 1.0))
        try loopStored("the running bolus") { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == true }
        }

        try harness.control.disconnectPump()

        try loopStored("the bolus finished after the link came back", syncing: true, until: Self.hasFinalizedBolus)
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.count, 1, "one bolus: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.value ?? 0, 1.0, accuracy: 1e-9)
    }

    func testABolusProgrammedOnThePumpIsStoredByLoopOnceFinished() throws {
        try pairLoop()
        try control.send(.init(command: .setFeatureFlag, featureFlag: TandemFeatureFlags.Flag.historyDoseReporting.rawValue, enabled: true))
        try waitForTheDriversFirstHistoryRead()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try harness.client.startBolus(units: 1.0, source: "pump")

        try loopStored("the pump's bolus", syncing: true) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false && $0.dose?.wasProgrammedByPumpUI == true }
        }
        let boluses = try liveBoluses(assertLoopStoredWhatTheOracleExpects().doses)
        XCTAssertEqual(boluses.count, 1, "one bolus: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.value ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.automatic, false)
    }

    private func liveBoluses(_ doses: [LoopCachedDose]) -> [LoopCachedDose] {
        doses.filter { $0.isBolus && !$0.isDeleted }
    }

    private static func hasFinalizedBolus(_ events: [NewPumpEvent]) -> Bool {
        events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
    }
}
