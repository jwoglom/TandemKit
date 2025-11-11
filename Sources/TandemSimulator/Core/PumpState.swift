import Foundation
import TandemCore

/// Simulated pump state implementation
class SimulatedPumpState: PumpStateProvider {
    // MARK: - Device Info

    let serialNumber: String
    let modelNumber: String
    let firmwareVersion: String

    // MARK: - Insulin Delivery

    var currentBasalRate: Double
    var activeProfile: String
    var reservoirLevel: Double
    var insulinOnBoard: Double = 0.0

    // MARK: - Active Bolus

    var activeBolusAmount: Double?
    var activeBolusStartTime: Date?

    // MARK: - CGM

    var cgmEnabled: Bool
    var currentGlucose: Int?
    var glucoseTrend: GlucoseTrend?

    // MARK: - Battery & Power

    var batteryPercent: Int
    var isCharging: Bool = false

    // MARK: - Time

    let pumpStartTime: Date

    var timeSinceReset: UInt32 {
        UInt32(Date().timeIntervalSince(pumpStartTime))
    }

    // MARK: - Settings

    var basalIQEnabled: Bool = false
    var controlIQEnabled: Bool = false
    var maxBasalRate: Double = 15.0
    var maxBolusAmount: Double = 25.0

    // MARK: - Alerts & Alarms

    var activeAlerts: Set<String> = []
    var activeReminders: Set<String> = []

    // MARK: - History

    private var historyEntries: [HistoryEntry] = []
    private let historyLock = NSLock()

    // MARK: - Initialization

    init(config: SimulatorConfig) {
        self.serialNumber = config.serialNumber
        self.modelNumber = config.pumpModel.modelNumber
        self.firmwareVersion = config.firmwareVersion
        self.currentBasalRate = config.currentBasalRate
        self.activeProfile = config.activeProfile
        self.reservoirLevel = config.reservoirLevel
        self.cgmEnabled = config.cgmEnabled
        self.currentGlucose = config.cgmEnabled ? config.currentGlucose : nil
        self.batteryPercent = config.batteryPercent
        self.pumpStartTime = Date()

        // Set default glucose trend if CGM is enabled
        if cgmEnabled {
            self.glucoseTrend = .stable
        }
    }

    // MARK: - History Management

    func addHistoryEntry(_ entry: HistoryEntry) {
        historyLock.lock()
        defer { historyLock.unlock() }

        historyEntries.append(entry)

        // Keep only last 1000 entries
        if historyEntries.count > 1000 {
            historyEntries.removeFirst(historyEntries.count - 1000)
        }
    }

    func getHistoryEntries(count: Int) -> [HistoryEntry] {
        historyLock.lock()
        defer { historyLock.unlock() }

        let actualCount = min(count, historyEntries.count)
        return Array(historyEntries.suffix(actualCount))
    }

    // MARK: - State Updates

    /// Simulate IOB decay over time (simplified model)
    func updateInsulinOnBoard() {
        guard let bolusStart = activeBolusStartTime,
              let bolusAmount = activeBolusAmount else {
            insulinOnBoard = max(0, insulinOnBoard - 0.01) // Slow decay
            return
        }

        let elapsed = Date().timeIntervalSince(bolusStart)
        let hoursElapsed = elapsed / 3600.0

        // Simple linear decay over 4 hours
        let decayRate = bolusAmount / 4.0
        let remaining = max(0, bolusAmount - (decayRate * hoursElapsed))

        insulinOnBoard = remaining

        // Clear active bolus if complete
        if remaining == 0 {
            activeBolusAmount = nil
            activeBolusStartTime = nil
        }
    }

    /// Update battery level (simulate slow drain)
    func updateBattery() {
        if !isCharging && batteryPercent > 0 {
            // Drain very slowly
            if Int.random(in: 0..<1000) == 0 {
                batteryPercent = max(0, batteryPercent - 1)
            }
        }
    }

    /// Simulate CGM reading variation
    func updateGlucose() {
        guard cgmEnabled, let current = currentGlucose else { return }

        // Small random variation (-5 to +5 mg/dL)
        let variation = Int.random(in: -5...5)
        let newValue = max(40, min(400, current + variation))

        currentGlucose = newValue

        // Update trend based on change
        if variation > 2 {
            glucoseTrend = .rising
        } else if variation < -2 {
            glucoseTrend = .falling
        } else {
            glucoseTrend = .stable
        }
    }
}
