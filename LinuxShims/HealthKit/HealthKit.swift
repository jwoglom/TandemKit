// Linux-only stand-in for Apple's HealthKit.
//
// Only the handful of symbols TandemKit actually touches: HKUnit and
// HKQuantity (LoopKit's currency for doses and limits) and HKDevice (one
// struct literal in TandemPumpManagerState). Never compiled on Apple
// platforms -- see LinuxShims/README.md.
@_exported import Foundation

// MARK: - Lightweight HealthKit shims

public struct HKUnit: Codable, Equatable {
    private let symbol: String

    public init(symbol: String) {
        self.symbol = symbol
    }

    public static func internationalUnit() -> HKUnit {
        HKUnit(symbol: "IU")
    }

    public static func internationalUnitPerHour() -> HKUnit {
        HKUnit(symbol: "IU/hr")
    }

    public static func hour() -> HKUnit {
        HKUnit(symbol: "hr")
    }

    public func unitDivided(by unit: HKUnit) -> HKUnit {
        HKUnit(symbol: "\(symbol)/\(unit.symbol)")
    }
}

public struct HKQuantity: Codable, Equatable {
    public let unit: HKUnit
    public let value: Double

    public init(unit: HKUnit, doubleValue: Double) {
        self.unit = unit
        value = doubleValue
    }

    public func doubleValue(for _: HKUnit) -> Double {
        value
    }
}

public struct HKDevice: Equatable {
    public var name: String?
    public var manufacturer: String?
    public var model: String?
    public var hardwareVersion: String?
    public var firmwareVersion: String?
    public var softwareVersion: String?
    public var localIdentifier: String?
    public var udiDeviceIdentifier: String?

    public init(
        name: String?,
        manufacturer: String?,
        model: String?,
        hardwareVersion: String?,
        firmwareVersion: String?,
        softwareVersion: String?,
        localIdentifier: String?,
        udiDeviceIdentifier: String?
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.hardwareVersion = hardwareVersion
        self.firmwareVersion = firmwareVersion
        self.softwareVersion = softwareVersion
        self.localIdentifier = localIdentifier
        self.udiDeviceIdentifier = udiDeviceIdentifier
    }
}
