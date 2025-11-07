// Compatibility stubs to allow building TandemKit on platforms without the full LoopKit framework.
//
// When building with Carthage on iOS/macOS, the real LoopKit framework from
// Carthage/Checkouts/LoopKit is used instead of these stubs.
//
// These stubs mirror the essential LoopKit interfaces that TandemKit requires,
// allowing standalone development, testing, and Linux builds.

import Foundation
import HealthKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Device Manager

public protocol DeviceManagerDelegate {
    #if canImport(UserNotifications)
    func scheduleNotification(for manager: DeviceManager,
                              identifier: String,
                              content: UNNotificationContent,
                              trigger: UNNotificationTrigger?)
    func clearNotification(for manager: DeviceManager, identifier: String)
    #endif
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?)
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
    var delegateQueue: DispatchQueue! { get set }

    init?(rawState: RawStateValue)
    var rawState: RawStateValue { get }
}

public extension DeviceManager {
    var localizedTitle: String {
        return type(of: self).localizedTitle
    }
}

// MARK: - Pump Manager Status

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
        case none
        case initiating
        case inProgress(_ dose: DoseEntry)
        case canceling
    }

    public let timeZone: TimeZone
    public let device: HKDevice
    public var pumpBatteryChargeRemaining: Double?
    public var basalDeliveryState: BasalDeliveryState
    public var bolusState: BolusState

    public init(
        timeZone: TimeZone,
        device: HKDevice,
        pumpBatteryChargeRemaining: Double?,
        basalDeliveryState: BasalDeliveryState,
        bolusState: BolusState
    ) {
        self.timeZone = timeZone
        self.device = device
        self.pumpBatteryChargeRemaining = pumpBatteryChargeRemaining
        self.basalDeliveryState = basalDeliveryState
        self.bolusState = bolusState
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
    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool)
    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError)
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (_ error: Error?) -> Void)
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (_ result: PumpManagerResult<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool)>) -> Void)
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval)
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager)
    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager)
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date
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
    case failure(Error)
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
    func roundToSupportedBasalRate(unitsPerHour: Double) -> Double
    func roundToSupportedBolusVolume(units: Double) -> Double

    var supportedBasalRates: [Double] { get }
    var supportedBolusVolumes: [Double] { get }
    var maximumBasalScheduleEntryCount: Int { get }
    var minimumBasalScheduleEntryDuration: TimeInterval { get }

    var pumpManagerDelegate: PumpManagerDelegate? { get set }
    var pumpRecordsBasalProfileStartEvents: Bool { get }
    var pumpReservoirCapacity: Double { get }
    var lastReconciliation: Date? { get }
    var status: PumpManagerStatus { get }

    var dosingDecisionDelegate: PumpManagerDosingDecisionDelegate? { get set }

    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue)
    func removeStatusObserver(_ observer: PumpManagerStatusObserver)

    func assertCurrentPumpData()
    func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool)
    func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter?

    func enactBolus(units: Double, at startDate: Date, willRequest: @escaping (_ dose: DoseEntry) -> Void, completion: @escaping (_ result: PumpManagerResult<DoseEntry>) -> Void)
    func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void)
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (_ result: PumpManagerResult<DoseEntry>) -> Void)
    func suspendDelivery(completion: @escaping (_ error: Error?) -> Void)
    func resumeDelivery(completion: @escaping (_ error: Error?) -> Void)
}

@available(macOS 13.0, iOS 14.0, *)
public extension PumpManager {
    func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        return supportedBasalRates.filter({$0 <= unitsPerHour}).max() ?? 0
    }

    func roundToSupportedBolusVolume(units: Double) -> Double {
        return supportedBolusVolumes.filter({$0 <= units}).max() ?? 0
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

// MARK: - Dose Types

@available(macOS 13.0, iOS 14.0, *)
public enum DoseType: String {
    case basal
    case bolus
    case resume
    case suspend
    case tempBasal
}

@available(macOS 13.0, iOS 14.0, *)
public enum DoseUnit: String {
    case units
    case unitsPerHour
}

@available(macOS 13.0, iOS 14.0, *)
public struct DoseEntry: Equatable {
    public let type: DoseType
    public let startDate: Date
    public let endDate: Date?
    public let value: Double
    public let unit: DoseUnit
    public let deliveredUnits: Double?
    public let syncIdentifier: String?
    public let scheduledBasalRate: HKQuantity?

    public init(
        type: DoseType,
        startDate: Date,
        endDate: Date? = nil,
        value: Double,
        unit: DoseUnit,
        deliveredUnits: Double? = nil,
        syncIdentifier: String? = nil,
        scheduledBasalRate: HKQuantity? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unit = unit
        self.deliveredUnits = deliveredUnits
        self.syncIdentifier = syncIdentifier
        self.scheduledBasalRate = scheduledBasalRate
    }
}

// MARK: - Reservoir and Events

@available(macOS 13.0, iOS 14.0, *)
public struct ReservoirValue {
    public let startDate: Date
    public let unitVolume: Double

    public init(startDate: Date, unitVolume: Double) {
        self.startDate = startDate
        self.unitVolume = unitVolume
    }
}

@available(macOS 13.0, iOS 14.0, *)
public enum PumpEventType: String {
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
public struct NewPumpEvent {
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

// MARK: - Errors

public enum PumpManagerError: Error {
    case communication(Error)
    case deviceState(Error)
    case configuration(Error)
}

// MARK: - CGM Manager

public protocol CGMManagerUI {}
