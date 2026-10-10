import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// faketandem does not send the cartridge wizards' state-stream notifications, so the wizards' pump
/// steps are not run here: what reaches Trio is the suspend around them and the changes they report.
final class TrioCartridgeTests: TrioTestCase {
    func testACartridgeAndSiteChangeAreStoredByTrioAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()
        try control.send(.init(command: .suspend))
        let suspended = try trioStored("the suspend") { events in
            events.contains { $0.type == .suspend }
        }

        try control.send(.init(command: .recordCartridgeChange))
        try control.send(.init(command: .recordSiteChange, units: 0.3))
        try waitForASecondToPass(since: XCTUnwrap(suspended.flatMap(\.pumpEvents).last { $0.type == .suspend }?.date))
        try control.send(.init(command: .resume))

        try trioStored("the resume") { events in
            events.contains { $0.type == .resume }
        }
        let stored = try assertTrioStoredWhatTheOracleExpects().stored
        XCTAssertEqual(
            stored.compactMap(\.eventType).filter { $0 != .tempBasal },
            [.pumpSuspend, .rewind, .siteChange, .pumpResume],
            "\(stored)"
        )
    }
}
