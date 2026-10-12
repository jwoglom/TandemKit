import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class LoopOnboardingTests: LoopTestCase {
    /// The manager Loop's pump setup screen builds from Loop's limits and basal schedule. Loop holds it
    /// from launch here, as when re-pairing, since the test cannot drive the screen.
    override func seededFiles() throws -> [String: String] {
        let setup = TandemPumpManagerState(
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.scheduledBasalRate)])!,
            maxBasalRateUnitsPerHour: Self.maxBasal,
            maxBolusUnits: Self.maxBolus
        )
        var files = try super.seededFiles()
        files["Documents/PumpManagerState.plist"] = try Self.plist(["managerIdentifier": "TandemPumpManager", "state": setup.rawValue])
        return files
    }

    func testPairingWithThePumpsCodeAndApplyingLoopsSettingsLetsLoopDose() throws {
        // Setup applies the settings straight after pairing, before any sync.
        try pairLoop(withCode: true, thenSync: false)

        try control.send(.init(command: .applyOnboardingSettings))

        let pump = try harness.client.snapshot()
        XCTAssertEqual(pump.idpProfiles?.first?.segments.map(\.basalRate), [Self.milliunits(Self.scheduledBasalRate)])
        XCTAssertEqual(pump.limits?.maxBasalMilliunits, Self.milliunits(Self.maxBasal))
        XCTAssertEqual(pump.limits?.maxBolusMilliunits, Self.milliunits(Self.maxBolus))
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))
        try loopStored("the cancelled temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let temps = try assertLoopStoredWhatTheOracleExpects().doses.filter { $0.isTempBasal && !$0.isDeleted }
        XCTAssertEqual(temps.map(\.programmedTempBasalRate), [1.5])
    }
}
