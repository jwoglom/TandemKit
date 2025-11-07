import Foundation
import TandemCore

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public static let version = 1

    public var pumpState: PumpState?
    public var lastReconciliation: Date?
    public var settings: TandemPumpManagerSettings
    public var latestInsulinOnBoard: Double?

    public init(
        pumpState: PumpState?,
        lastReconciliation: Date? = nil,
        settings: TandemPumpManagerSettings = .default,
        latestInsulinOnBoard: Double? = nil
    ) {
        self.pumpState = pumpState
        self.lastReconciliation = lastReconciliation
        self.settings = settings
        self.latestInsulinOnBoard = latestInsulinOnBoard
    }

    public init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == TandemPumpManagerState.version else {
            return nil
        }

        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            self.pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            self.pumpState = nil
        }

        if let lastReconciliationInterval = rawValue["lastReconciliation"] as? TimeInterval {
            self.lastReconciliation = Date(timeIntervalSinceReferenceDate: lastReconciliationInterval)
        } else {
            self.lastReconciliation = nil
        }

        if let settingsRaw = rawValue["settings"] as? TandemPumpManagerSettings.RawValue,
           let settings = TandemPumpManagerSettings(rawValue: settingsRaw) {
            self.settings = settings
        } else {
            self.settings = .default
        }

        if let latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double {
            self.latestInsulinOnBoard = latestInsulinOnBoard
        } else {
            self.latestInsulinOnBoard = nil
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": TandemPumpManagerState.version
        ]

        if let pumpState = pumpState {
            raw["pumpState"] = pumpState.rawValue
        }

        if let lastReconciliation = lastReconciliation {
            raw["lastReconciliation"] = lastReconciliation.timeIntervalSinceReferenceDate
        }

        let settingsRaw = settings.rawValue
        if !settingsRaw.isEmpty {
            raw["settings"] = settingsRaw
        }

        if let latestInsulinOnBoard = latestInsulinOnBoard {
            raw["latestInsulinOnBoard"] = latestInsulinOnBoard
        }

        return raw
    }
}
