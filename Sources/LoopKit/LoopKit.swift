#if os(Linux)

import Foundation

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

    public func unitDivided(by unit: HKUnit) -> HKUnit {
        HKUnit(symbol: "\(symbol)/\(unit.symbol)")
    }
}

public struct HKQuantity: Codable, Equatable {
    public let unit: HKUnit
    public let value: Double

    public init(unit: HKUnit, doubleValue: Double) {
        self.unit = unit
        self.value = doubleValue
    }

    public func doubleValue(for unit: HKUnit) -> Double {
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

#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Shared Protocols & Helpers

public protocol TimelineValue {
    var startDate: Date { get }
    var endDate: Date { get }
}

public protocol DeviceStatusHighlight {
    var localizedMessage: String { get }
    var imageName: String { get }
    var state: DeviceStatusHighlightState { get }
}

public enum DeviceStatusHighlightState: String, Codable {
    case normal
    case warning
    case critical
}

public protocol DeviceLifecycleProgress {
    var percentComplete: Double { get }
    var progressState: DeviceLifecycleProgressState { get }
}

public enum DeviceLifecycleProgressState: String, Codable {
    case none
    case inProgress
    case completed
}

// MARK: - Device Manager

public protocol DeviceManagerDelegate {
#if canImport(UserNotifications)
    func scheduleNotification(
        for manager: DeviceManager,
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?
    )
    func clearNotification(for manager: DeviceManager, identifier: String)
#endif
    func deviceManager(
        _ manager: DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    )
}

public enum DeviceLogEntryType: String {
    case send
    case receive
    case error
    case connection
    case delegated
}

public protocol DeviceManager: AnyObject, CustomDebugStringConvertible {
    typealias RawStateValue = [String: Any]

    static var managerIdentifier: String { get }
    static var localizedTitle: String { get }
    var localizedTitle: String { get }

    init?(rawState: RawStateValue)
    var rawState: RawStateValue { get }
    var isOnboarded: Bool { get }
}

public extension DeviceManager {
    var localizedTitle: String {
        type(of: self).localizedTitle
    }
}

// MARK: - Pump Manager Status

@available(macOS 13.0, iOS 14.0, *)
public struct PumpStatusHighlight: DeviceStatusHighlight, Equatable {
    public var localizedMessage: String
    public var imageName: String
    public var state: DeviceStatusHighlightState

    public init(localizedMessage: String, imageName: String, state: DeviceStatusHighlightState) {
        self.localizedMessage = localizedMessage
        self.imageName = imageName
        self.state = state
    }
}

@available(macOS 13.0, iOS 14.0, *)
public struct PumpLifecycleProgress: DeviceLifecycleProgress, Equatable {
    public var percentComplete: Double
    public var progressState: DeviceLifecycleProgressState

    public init(percentComplete: Double, progressState: DeviceLifecycleProgressState) {
        self.percentComplete = percentComplete
        self.progressState = progressState
    }
}

@available(macOS 13.0, iOS 14.0, *)
public struct PumpManagerStatus: Equatable {
    public enum BasalDeliveryState: Equatable {
        case active(_ at: Date)
        case initiatingTempBasal
        case tempBasal(_ dose: DoseEntry)
        case cancelingTempBasal
        case suspending
        case suspended(_ at: Date)
        case resuming

        public var isSuspended: Bool {
            if case .suspended = self {
                return true
            }
            return false
        }
    }

    public enum BolusState: Equatable {
        case noBolus
        case initiating
        case inProgress(_ dose: DoseEntry)
        case canceling
    }

    public let timeZone: TimeZone
    public let device: HKDevice
    public var pumpBatteryChargeRemaining: Double?
    public var basalDeliveryState: BasalDeliveryState?
    public var bolusState: BolusState
    public var insulinType: InsulinType?
    public var deliveryIsUncertain: Bool

    public init(
        timeZone: TimeZone,
        device: HKDevice,
        pumpBatteryChargeRemaining: Double?,
        basalDeliveryState: BasalDeliveryState?,
        bolusState: BolusState,
        insulinType: InsulinType?,
        deliveryIsUncertain: Bool = false
    ) {
        self.timeZone = timeZone
        self.device = device
        self.pumpBatteryChargeRemaining = pumpBatteryChargeRemaining
        self.basalDeliveryState = basalDeliveryState
        self.bolusState = bolusState
        self.insulinType = insulinType
        self.deliveryIsUncertain = deliveryIsUncertain
    }
}

// MARK: - Pump Manager Delegates

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManagerStatusObserver: AnyObject {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus)
}

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManagerDelegate: DeviceManagerDelegate, PumpManagerStatusObserver {
    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager)
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager)
    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager)
    func pumpManager(
        _ pumpManager: PumpManager,
        didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool
    )
    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError)
    func pumpManager(
        _ pumpManager: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (_ error: Error?) -> Void
    )
    func pumpManager(
        _ pumpManager: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (
            _ result: Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>
        ) -> Void
    )
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval)
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager)
    func pumpManager(
        _ pumpManager: PumpManager,
        didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    )
    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager)
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date
    var detectedSystemTimeOffset: TimeInterval { get }
    var automaticDosingEnabled: Bool { get }
}

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManagerDosingDecisionDelegate: AnyObject {
    func pumpManager(_ pumpManager: PumpManager, didEnactBolus result: PumpManagerResult<DoseEntry>)
    func pumpManager(_ pumpManager: PumpManager, didCancelBolus result: PumpManagerResult<DoseEntry?>)
    func pumpManager(_ pumpManager: PumpManager, didEnactTempBasal result: PumpManagerResult<DoseEntry>)
    func pumpManager(_ pumpManager: PumpManager, didSuspendDeliveryWithError error: Error?)
    func pumpManager(_ pumpManager: PumpManager, didResumeDeliveryWithError error: Error?)
}

// MARK: - Pump Manager Protocol

@available(macOS 13.0, iOS 14.0, *)
public enum PumpManagerResult<T> {
    case success(T)
    case failure(PumpManagerError)
}

@available(macOS 13.0, iOS 14.0, *)
public protocol DoseProgressReporter {
    var progress: DoseProgress { get }
}

@available(macOS 13.0, iOS 14.0, *)
public struct DoseProgress {
    public let deliveredUnits: Double
    public let percentComplete: Double

    public init(deliveredUnits: Double, percentComplete: Double) {
        self.deliveredUnits = deliveredUnits
        self.percentComplete = percentComplete
    }
}

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManager: DeviceManager {
    static var onboardingMaximumBasalScheduleEntryCount: Int { get }
    static var onboardingSupportedBasalRates: [Double] { get }
    static var onboardingSupportedBolusVolumes: [Double] { get }
    static var onboardingSupportedMaximumBolusVolumes: [Double] { get }

    var delegateQueue: DispatchQueue! { get set }

    func roundToSupportedBasalRate(unitsPerHour: Double) -> Double
    func roundToSupportedBolusVolume(units: Double) -> Double

    var supportedBasalRates: [Double] { get }
    var supportedBolusVolumes: [Double] { get }
    var supportedMaximumBolusVolumes: [Double] { get }
    var maximumBasalScheduleEntryCount: Int { get }
    var minimumBasalScheduleEntryDuration: TimeInterval { get }

    var pumpManagerDelegate: PumpManagerDelegate? { get set }
    var pumpRecordsBasalProfileStartEvents: Bool { get }
    var pumpReservoirCapacity: Double { get }
    var lastSync: Date? { get }
    var status: PumpManagerStatus { get }

    var dosingDecisionDelegate: PumpManagerDosingDecisionDelegate? { get set }

    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue)
    func removeStatusObserver(_ observer: PumpManagerStatusObserver)

    func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?)
    func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool)
    func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter?
    func estimatedDuration(toBolus units: Double) -> TimeInterval

    func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    )
    func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void)
    func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    )
    func suspendDelivery(completion: @escaping (_ error: Error?) -> Void)
    func resumeDelivery(completion: @escaping (_ error: Error?) -> Void)

    func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void
    )
    func syncDeliveryLimits(
        limits deliveryLimits: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    )
    func prepareForDeactivation(_ completion: @escaping (Error?) -> Void)
}

@available(macOS 13.0, iOS 14.0, *)
public extension PumpManager {
    func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        supportedBasalRates.filter { $0 <= unitsPerHour }.max() ?? 0
    }

    func roundToSupportedBolusVolume(units: Double) -> Double {
        supportedBolusVolumes.filter { $0 <= units }.max() ?? 0
    }

    func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        notifyDelegateOfDeactivation { completion(nil) }
    }

    func notifyDelegateOfDeactivation(completion: @escaping () -> Void) {
        delegateQueue.async {
            self.pumpManagerDelegate?.pumpManagerWillDeactivate(self)
            completion()
        }
    }
}

// MARK: - Pump Manager UI

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManagerUI: PumpManager {
#if canImport(UIKit)
    func pairingViewController(onFinished: @escaping (Result<Void, Error>) -> Void) -> UIViewController
    func settingsViewController() -> UIViewController
    var smallImage: UIImage? { get }
#endif
}

// MARK: - Dose Types & Entries

@available(macOS 13.0, iOS 14.0, *)
public enum DoseType: String, Codable {
    case basal
    case bolus
    case resume
    case suspend
    case tempBasal
}

@available(macOS 13.0, iOS 14.0, *)
public enum DoseUnit: String, Codable {
    case units
    case unitsPerHour
}

@available(macOS 13.0, iOS 14.0, *)
public enum InsulinType: String, Codable {
    case rapidActingAnalog
    case ultraRapidActing
    case ultraRapidInsulin
    case longActing
    case unknown
}

@available(macOS 13.0, iOS 14.0, *)
public struct DoseEntry: TimelineValue, Equatable, Codable {
    public let type: DoseType
    public let startDate: Date
    public var endDate: Date
    public let value: Double
    public let unit: DoseUnit
    public let deliveredUnits: Double?
    public let description: String?
    public let insulinType: InsulinType?
    public let automatic: Bool?
    public let manuallyEntered: Bool
    public var syncIdentifier: String?
    public var scheduledBasalRate: HKQuantity?
    public let isMutable: Bool
    public let wasProgrammedByPumpUI: Bool

    public init(
        suspendDate: Date,
        automatic: Bool? = nil,
        isMutable: Bool = false,
        wasProgrammedByPumpUI: Bool = false
    ) {
        self.init(
            type: .suspend,
            startDate: suspendDate,
            value: 0,
            unit: .units,
            deliveredUnits: nil,
            description: nil,
            syncIdentifier: nil,
            scheduledBasalRate: nil,
            insulinType: nil,
            automatic: automatic,
            manuallyEntered: false,
            isMutable: isMutable,
            wasProgrammedByPumpUI: wasProgrammedByPumpUI
        )
    }

    public init(
        resumeDate: Date,
        insulinType: InsulinType? = nil,
        automatic: Bool? = nil,
        isMutable: Bool = false,
        wasProgrammedByPumpUI: Bool = false
    ) {
        self.init(
            type: .resume,
            startDate: resumeDate,
            value: 0,
            unit: .units,
            deliveredUnits: nil,
            description: nil,
            syncIdentifier: nil,
            scheduledBasalRate: nil,
            insulinType: insulinType,
            automatic: automatic,
            manuallyEntered: false,
            isMutable: isMutable,
            wasProgrammedByPumpUI: wasProgrammedByPumpUI
        )
    }

    public init(
        type: DoseType,
        startDate: Date,
        endDate: Date? = nil,
        value: Double,
        unit: DoseUnit,
        deliveredUnits: Double? = nil,
        description: String? = nil,
        syncIdentifier: String? = nil,
        scheduledBasalRate: HKQuantity? = nil,
        insulinType: InsulinType? = nil,
        automatic: Bool? = nil,
        manuallyEntered: Bool = false,
        isMutable: Bool = false,
        wasProgrammedByPumpUI: Bool = false
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate ?? startDate
        self.value = value
        self.unit = unit
        self.deliveredUnits = deliveredUnits
        self.description = description
        self.syncIdentifier = syncIdentifier
        self.scheduledBasalRate = scheduledBasalRate
        self.insulinType = insulinType
        self.automatic = automatic
        self.manuallyEntered = manuallyEntered
        self.isMutable = isMutable
        self.wasProgrammedByPumpUI = wasProgrammedByPumpUI
    }
}

// MARK: - Scheduling & Limits

@available(macOS 13.0, iOS 14.0, *)
public struct RepeatingScheduleValue<T>: Codable where T: Codable {
    public var startTime: TimeInterval
    public var value: T

    public init(startTime: TimeInterval, value: T) {
        self.startTime = startTime
        self.value = value
    }
}

@available(macOS 13.0, iOS 14.0, *)
public struct BasalRateSchedule: Codable, Equatable {
    public var items: [RepeatingScheduleValue<Double>]
    public var timeZone: TimeZone

    public init(items: [RepeatingScheduleValue<Double>], timeZone: TimeZone) {
        self.items = items
        self.timeZone = timeZone
    }
}

@available(macOS 13.0, iOS 14.0, *)
public struct DeliveryLimits: Codable, Equatable {
    public var maximumBasalRatePerHour: Double?
    public var maximumBolus: Double?

    public init(maximumBasalRatePerHour: Double?, maximumBolus: Double?) {
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
    }
}

// MARK: - Reservoir and Events

@available(macOS 13.0, iOS 14.0, *)
public protocol ReservoirValue {
    var startDate: Date { get }
    var unitVolume: Double { get }
}

@available(macOS 13.0, iOS 14.0, *)
public struct SimpleReservoirValue: ReservoirValue {
    public let startDate: Date
    public let unitVolume: Double

    public init(startDate: Date, unitVolume: Double) {
        self.startDate = startDate
        self.unitVolume = unitVolume
    }
}

@available(macOS 13.0, iOS 14.0, *)
public enum PumpEventType: String, Codable {
    case alarm
    case alarmClear
    case basal
    case bolus
    case prime
    case rewind
    case suspend
    case resume
    case tempBasal
}

@available(macOS 13.0, iOS 14.0, *)
public struct NewPumpEvent: Codable, Equatable {
    public let date: Date
    public let dose: DoseEntry?
    public let isMutable: Bool
    public let raw: Data
    public let title: String
    public let type: PumpEventType?

    public init(
        date: Date,
        dose: DoseEntry?,
        isMutable: Bool = false,
        raw: Data,
        title: String,
        type: PumpEventType?
    ) {
        self.date = date
        self.dose = dose
        self.isMutable = isMutable
        self.raw = raw
        self.title = title
        self.type = type
    }
}

// MARK: - Errors & Activation

@available(macOS 13.0, iOS 14.0, *)
public enum PumpManagerError: Error {
    case configuration(Error?)
    case connection(Error?)
    case communication(Error?)
    case deviceState(Error?)
    case uncertainDelivery
}

@available(macOS 13.0, iOS 14.0, *)
public enum BolusActivationType: String, Codable {
    case automatic
    case manualNoRecommendation
    case manualRecommendationAccepted
    case manualRecommendationChanged
    case none

    public var isAutomatic: Bool {
        self == .automatic
    }
}

// MARK: - CGM Manager

public protocol CGMManagerUI {}

#else

@_exported import LoopKitBinary

#endif
