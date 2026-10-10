import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioBolusTests: TrioTestCase {
    func testAnAppBolusIsStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 1.0))

        let batches = try trioStored("a finalized bolus", syncing: true) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
        }
        let stored = try assertTrioStoredWhatTheOracleExpects(batches).stored
        let boluses = stored.filter { $0.type == TrioDoseStoreOracle.EventType.bolus.rawValue }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.isSMB, false)
    }
}
