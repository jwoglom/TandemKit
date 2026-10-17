import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Trio's own loop: its glucose simulator for a CGM, closed loop on, SMBs allowed. Trio decides the
/// doses and enacts them through its APSManager, not the control channel.
final class TrioClosedLoopTests: TrioTestCase {
    /// Held near 250 mg/dL, far above Trio's default target, so every loop asks for insulin.
    /// `GlucoseSimulator_*` are UserDefaults the simulator reads; an amplitude of 0 means its default.
    override var launchArguments: [String] {
        ["-GlucoseSimulator_CenterValue", "250", "-GlucoseSimulator_Amplitude", "1", "-GlucoseSimulator_NoiseAmplitude", "1"]
    }

    /// Trio loops only on a reading of the simulator, 5 minutes apart, and its first is at launch, so
    /// it launches with the driver's state after a pairing: a pairing through the control channel
    /// after launch lost the race to that loop, and the next one was a reading later.
    private var pairedState: TandemPumpManagerState!

    override func beforeLaunch() throws {
        try super.beforeLaunch()
        var state = try TandemPumpManagerState(
            basalRateSchedule: XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.scheduledBasalRate)])),
            maxBasalRateUnitsPerHour: Self.maxBasal,
            maxBolusUnits: Self.maxBolus
        )
        state.pumpState.derivedSecret = try seedLongTermKey()
        state.pumpState.pincode = FaketandemHarness.pairingCode
        // The id faketandem sends in every hello, which the driver's connect checks against.
        state.pumpState.peripheralUuid = try harness.readHello().peripheralId.uuidString
        state.hasSyncedBasalRateSchedule = true
        pairedState = state
        // The pump already runs the schedule, so the first sync queues no profile update.
        let profile = FaketandemIDPProfile(id: 1, segments: [.init(startTime: 0, basalRate: Self.milliunits(Self.scheduledBasalRate))])
        try harness.client.setState([
            "idp_profiles": [profile.fields],
            "basal_rate": Self.scheduledBasalRate,
            "bolus_rate_units_per_second": 0.25,
        ])
    }

    override func seededFiles() throws -> [String: String] {
        var files = try super.seededFiles()
        files["Documents/freeaps/freeaps_settings.json"] = try Self.json(["cgm": "simulator", "dosingMode": "closed"])
        files["Documents/PumpManagerState.plist"] = try Self.plist(["managerIdentifier": "TandemPumpManager", "state": pairedState.rawValue])
        return files
    }

    /// Trio's default max IOB of 0 allows no insulin above the profile.
    override var preferences: [String: Any] {
        super.preferences.merging(["max_iob": 5, "enableSMB_always": true]) { _, new in new }
    }

    func testTrioLoopEnactsATempBasalAndAnSMBThatTrioStoresAsTheOracleExpects() throws {
        try trioStored("a temp basal and an SMB from Trio's loop", timeout: 900) { events in
            events.contains { $0.dose?.type == .tempBasal && $0.dose?.automatic == true }
                && events.contains { $0.dose?.type == .bolus && $0.dose?.automatic == true }
        }
        try trioStored("the SMB finished", syncing: true) { events in
            events.contains { $0.dose?.type == .bolus && $0.dose?.automatic == true && $0.dose?.isMutable == false }
        }

        let stored = try assertTrioStoredWhatTheOracleExpects().stored
        let temps = stored.filter(\.isTempBasal)
        XCTAssertFalse(temps.isEmpty, "\(stored)")
        XCTAssertTrue(temps.allSatisfy { ($0.tempBasalRate ?? .infinity) <= Self.maxBasal }, "\(temps)")
        let smbs = stored.filter { $0.eventType == .bolus }
        XCTAssertFalse(smbs.isEmpty, "\(stored)")
        XCTAssertTrue(smbs.allSatisfy { $0.isSMB == true }, "\(smbs)")
    }
}
