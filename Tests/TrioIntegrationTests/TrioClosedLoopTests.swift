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

    override func seededFiles() throws -> [String: String] {
        var files = try super.seededFiles()
        files["Documents/freeaps/freeaps_settings.json"] = try Self.json(["cgm": "simulator", "dosingMode": "closed"])
        return files
    }

    /// Trio's default max IOB of 0 allows no insulin above the profile.
    override var preferences: [String: Any] {
        super.preferences.merging(["max_iob": 5, "enableSMB_always": true]) { _, new in new }
    }

    func testTrioLoopEnactsATempBasalAndAnSMBThatTrioStoresAsTheOracleExpects() throws {
        try pairTrio()
        try syncBasalSchedule()
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        // The simulator gives a reading every 5 minutes and Trio loops on each; the loop at launch
        // found the pump unpaired.
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
