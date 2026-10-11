import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// faketandem does not send the cartridge wizards' state-stream notifications, so the wizards' pump
/// steps are not run here: what reaches Loop is the suspend around them and the changes they report.
final class LoopCartridgeTests: LoopTestCase {
    func testACartridgeAndSiteChangeAreStoredByLoopAsTheOracleExpects() throws {
        try pairLoop()
        try syncBasalSchedule()
        try control.send(.init(command: .suspend))
        try loopStored("the suspend") { events in
            events.contains { $0.type == .suspend }
        }

        try control.send(.init(command: .recordCartridgeChange))
        try control.send(.init(command: .recordSiteChange, units: 0.3))
        try control.send(.init(command: .resume))

        try loopStored("the resume") { events in
            events.contains { $0.type == .resume }
        }
        let events = try assertLoopStoredWhatTheOracleExpects().events
        let basal = [PumpEventType.basal, .tempBasal].map(\.rawValue)
        XCTAssertEqual(
            events.compactMap(\.type).filter { !basal.contains($0) },
            [PumpEventType.suspend, .rewind, .replaceComponent(componentType: .infusionSet), .resume].map(\.rawValue),
            "\(events)"
        )
    }
}
