import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Loop's own loop, closed, on its CGM simulator held far above the correction range. Loop loops at most
/// every 4.2 minutes, and the loop at launch finds the pump unpaired.
class LoopClosedLoopTestCase: LoopTestCase {
    override var dosingEnabled: Bool {
        true
    }

    /// MockCGMManager restored from its state (LoopKit MockCGMDataSource raw values): a constant
    /// glucose, a reading every minute (`MeasurementFrequency.fast`).
    override func seededFiles() throws -> [String: String] {
        var files = try super.seededFiles()
        files["Documents/CGMManagerState.plist"] = try Self.plist([
            "managerIdentifier": "MockCGMManager",
            "state": [
                "dataSource": [
                    "model": ["kind": "constant", "quantity": 250.0],
                    "effects": [String: Any](),
                    "dataPointFrequency": 1,
                ] as [String: Any],
            ],
        ])
        return files
    }

    func pairAndWaitForLoop(_ what: String, until condition: @escaping ([NewPumpEvent]) -> Bool) throws {
        try pairLoop()
        try syncBasalSchedule()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])
        try loopStored(what, timeout: 900, until: condition)
    }
}

final class LoopTempBasalOnlyClosedLoopTests: LoopClosedLoopTestCase {
    func testLoopEnactsAnAutomaticTempBasalThatLoopStoresAsTheOracleExpects() throws {
        try pairAndWaitForLoop("an automatic temp basal from Loop's loop") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.automatic == true }
        }

        let doses = try assertLoopStoredWhatTheOracleExpects().doses
        let temps = doses.filter { $0.isTempBasal && !$0.isDeleted }
        XCTAssertFalse(temps.isEmpty, "\(doses)")
        XCTAssertTrue(temps.allSatisfy { $0.automatic == true }, "\(temps)")
        XCTAssertTrue(temps.allSatisfy { ($0.programmedTempBasalRate ?? .infinity) <= Self.maxBasal }, "\(temps)")
        XCTAssertTrue(doses.filter(\.isBolus).isEmpty, "temp basal only: \(doses)")
    }
}

final class LoopAutomaticBolusClosedLoopTests: LoopClosedLoopTestCase {
    override var dosingStrategy: Int {
        1
    }

    func testLoopEnactsAnAutomaticBolusThatLoopStoresAsTheOracleExpects() throws {
        try pairAndWaitForLoop("an automatic bolus from Loop's loop") { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.automatic == true }
        }
        try loopStored("the automatic bolus finished", syncing: true) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.automatic == true && $0.dose?.isMutable == false }
        }

        let doses = try assertLoopStoredWhatTheOracleExpects().doses
        let boluses = doses.filter { $0.isBolus && !$0.isDeleted }
        XCTAssertFalse(boluses.isEmpty, "\(doses)")
        XCTAssertTrue(boluses.allSatisfy { $0.automatic == true }, "\(boluses)")
        XCTAssertTrue(boluses.allSatisfy { $0.value <= Self.maxBolus }, "\(boluses)")
    }
}
