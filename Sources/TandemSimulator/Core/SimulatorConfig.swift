import Foundation

/// Configuration for the pump simulator
struct SimulatorConfig {
    // MARK: - Device Identity

    /// Pump model to simulate
    var pumpModel: PumpModel = .tslimX2

    /// Serial number for the simulated pump
    var serialNumber: String = "SIM12345"

    /// Firmware version to report
    var firmwareVersion: String = "7.7.0"

    // MARK: - Pairing

    /// Pre-set pairing code (6-digit for JPAKE or 16-char for legacy)
    var pairingCode: String?

    /// Authentication mode to use
    var authenticationMode: AuthMode = .jpake

    // MARK: - Initial State

    /// Initial insulin reservoir level in units
    var reservoirLevel: Double = 250.0

    /// Initial battery percentage (0-100)
    var batteryPercent: Int = 85

    /// Current basal rate in U/hr
    var currentBasalRate: Double = 1.0

    /// Active profile name
    var activeProfile: String = "Profile 1"

    /// Whether CGM is enabled
    var cgmEnabled: Bool = true

    /// Current glucose reading in mg/dL (if CGM enabled)
    var currentGlucose: Int = 120

    // MARK: - Transport

    /// Use mock in-memory transport instead of BLE
    var useMockTransport: Bool = false

    // MARK: - Behavior

    /// Send periodic qualifying event notifications
    var sendPeriodicNotifications: Bool = false

    /// Interval for periodic notifications (seconds)
    var notificationInterval: TimeInterval = 300

    /// Simulate realistic response delays
    var simulateRealisticDelays: Bool = true

    /// Response delay in milliseconds
    var responseDelayMs: Int = 50
}

enum PumpModel: String {
    case tslimX2 = "T:slim X2"
    case mobi = "Mobi"

    var modelNumber: String {
        switch self {
        case .tslimX2: return "T54"
        case .mobi: return "T62"
        }
    }
}

enum AuthMode {
    case jpake // 6-digit pairing code
    case legacy // 16-character pairing code
    case bypass // Skip authentication for testing
}
