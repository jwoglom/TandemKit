import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Loop next-dev set no pump delegate queue, the driver held every report, and Loop enacted the same
/// bolus every cycle while storing none of them (#637). Every `LoopTestCase` now waits for the driver
/// to report to Loop at launch; these pin the contract on its own.
final class LoopReportingTests: LoopTestCase {
    /// Loop loops at most every 4.2 minutes.
    static let wellInsideALoopCycle: TimeInterval = 60

    func testTheDriverReportsToLoopFromLaunch() throws {
        let status = try XCTUnwrap(control.send(.init(command: .status)).status)

        XCTAssertTrue(status.delegateAttached)
        XCTAssertTrue(status.reportsToDelegate)
        XCTAssertEqual(status.heldPumpEventBatches, 0)
    }

    func testABolusLoopEnactsIsInItsStoreWhileTheBolusRuns() throws {
        try pairLoop()

        // 2 U at the emulator's default 0.05 U/s runs for 40 s.
        try control.send(.init(command: .bolus, units: 2.0))

        try loopStored("the running bolus", timeout: Self.wellInsideALoopCycle) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.isMutable == true }
        }
        let boluses = try assertLoopStoredWhatTheOracleExpects().doses.filter { $0.isBolus && !$0.isDeleted }
        XCTAssertEqual(boluses.count, 1, "\(boluses)")
    }
}
