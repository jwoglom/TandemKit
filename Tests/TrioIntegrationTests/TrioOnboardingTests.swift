import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TrioOnboardingTests: TrioTestCase {
    /// The manager Trio's pump setup screen creates before it pairs, from Trio's own limits and basal
    /// profile, as Trio had saved it.
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

    func testPairingWithThePumpsCodeAndApplyingTrioSettingsLetsTrioDose() throws {
        // Setup applies the settings straight after pairing, before any sync.
        try pairTrio(withCode: true, thenSync: false)

        try control.send(.init(command: .applyOnboardingSettings))

        let pump = try harness.client.snapshot()
        XCTAssertEqual(pump.idpProfiles?.first?.segments.map(\.basalRate), [Self.milliunits(Self.scheduledBasalRate)])
        XCTAssertEqual(pump.limits?.maxBasalMilliunits, Self.milliunits(Self.maxBasal))
        XCTAssertEqual(pump.limits?.maxBolusMilliunits, Self.milliunits(Self.maxBolus))
        try control.send(.init(command: .tempBasal, unitsPerHour: 1.5, duration: .minutes(30)))
        try control.send(.init(command: .tempBasal, unitsPerHour: 0, duration: 0))
        try trioStored("the cancelled temp basal") { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        }
        let temps = try assertTrioStoredWhatTheOracleExpects().stored.filter(\.isTempBasal)
        XCTAssertEqual(temps.map(\.tempBasalRate), [1.5])
    }
}
