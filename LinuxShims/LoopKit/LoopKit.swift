@_exported import Foundation
// Re-exported, as real LoopKit does.
@_exported import HealthKit

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(UserNotifications)
    import UserNotifications
#endif

// This file is a shim for building on non-Apple platforms.
#if os(Linux)

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

    public protocol DeviceManagerDelegate: AlertIssuer, AnyObject {
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
        case delegate
        case delegateResponse
        case connection
    }

    public protocol DeviceManager: AnyObject, CustomDebugStringConvertible {
        typealias RawStateValue = [String: Any]

        static var managerIdentifier: String { get }
        var localizedTitle: String { get }

        init?(rawState: RawStateValue)
        var rawState: RawStateValue { get }
        var isOnboarded: Bool { get }
    }

    // MARK: - Pump Manager Status

    @available(macOS 13.0, iOS 14.0, *) public struct PumpStatusHighlight: DeviceStatusHighlight, Equatable {
        public var localizedMessage: String
        public var imageName: String
        public var state: DeviceStatusHighlightState

        public init(localizedMessage: String, imageName: String, state: DeviceStatusHighlightState) {
            self.localizedMessage = localizedMessage
            self.imageName = imageName
            self.state = state
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public struct PumpLifecycleProgress: DeviceLifecycleProgress, Equatable {
        public var percentComplete: Double
        public var progressState: DeviceLifecycleProgressState

        public init(percentComplete: Double, progressState: DeviceLifecycleProgressState) {
            self.percentComplete = percentComplete
            self.progressState = progressState
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public struct PumpManagerStatus: Equatable {
        public enum BasalDeliveryState: Equatable {
            case active(_ at: Date)
            case initiatingTempBasal
            case tempBasal(_ dose: DoseEntry)
            case cancelingTempBasal
            case suspending
            case suspended(_ at: Date)
            case resuming
            case pumpInoperable

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

    @available(macOS 13.0, iOS 14.0, *) public enum AutomatedTreatmentState: Equatable {
        case neutralNoOverride
        case neutralOverride
        case increasedInsulin
        case decreasedInsulin
        case minimumDelivery
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol PumpManagerStatusObserver: AnyObject {
        func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus)
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol PumpManagerDelegate: DeviceManagerDelegate, PumpManagerStatusObserver,
        AnyObject
    {
        func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager)
        func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool
        func pumpManagerWantsDeletion(_ pumpManager: PumpManager) async
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
        func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date
        var detectedSystemTimeOffset: TimeInterval { get }
        var automaticDosingEnabled: Bool { get }
        var automatedTreatmentState: AutomatedTreatmentState? { get }
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol PumpManagerDosingDecisionDelegate: AnyObject {
        func pumpManager(_ pumpManager: PumpManager, didEnactBolus result: PumpManagerResult<DoseEntry>)
        func pumpManager(_ pumpManager: PumpManager, didCancelBolus result: PumpManagerResult<DoseEntry?>)
        func pumpManager(_ pumpManager: PumpManager, didEnactTempBasal result: PumpManagerResult<DoseEntry>)
        func pumpManager(_ pumpManager: PumpManager, didSuspendDeliveryWithError error: Error?)
        func pumpManager(_ pumpManager: PumpManager, didResumeDeliveryWithError error: Error?)
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol AlertIssuer: AnyObject {
        @MainActor
        func issueAlert(_ alert: Alert) async
        @MainActor
        func retractAlert(identifier: Alert.Identifier) async
    }

    // MARK: - Pump Manager Protocol

    @available(macOS 13.0, iOS 14.0, *) public enum PumpManagerResult<T> {
        case success(T)
        case failure(PumpManagerError)
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol DoseProgressReporter: AnyObject {
        var progress: DoseProgress { get }

        func addObserver(_ observer: DoseProgressObserver)

        func removeObserver(_ observer: DoseProgressObserver)
    }

    @available(macOS 13.0, iOS 14.0, *) public struct DoseProgress {
        public let deliveredUnits: Double
        public let percentComplete: Double

        public init(deliveredUnits: Double, percentComplete: Double) {
            self.deliveredUnits = deliveredUnits
            self.percentComplete = percentComplete
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol PumpManager: DeviceManager {
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


        func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue)
        func removeStatusObserver(_ observer: PumpManagerStatusObserver)

        func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?)
        func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool)
        func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter?
        func estimatedDuration(toBolus units: Double) -> TimeInterval

        func enactBolus(
            decisionId: UUID?,
            units: Double,
            activationType: BolusActivationType,
            completion: @escaping (_ error: PumpManagerError?) -> Void
        )
        func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void)
        func enactTempBasal(
            decisionId: UUID?,
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
        func delete() async
    }

    @available(macOS 13.0, iOS 14.0, *) public extension PumpManager {
        func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
            supportedBasalRates.filter { $0 <= unitsPerHour }.max() ?? 0
        }

        func roundToSupportedBolusVolume(units: Double) -> Double {
            supportedBolusVolumes.filter { $0 <= units }.max() ?? 0
        }

        func delete() async {
            await pumpManagerDelegate?.pumpManagerWantsDeletion(self)
        }
    }

    // MARK: - Pump Manager UI

    @available(macOS 13.0, iOS 14.0, *) public protocol PumpManagerUI: PumpManager {
        #if canImport(UIKit)
            func pairingViewController(onFinished: @escaping (Result<Void, Error>) -> Void) -> UIViewController
            func settingsViewController() -> UIViewController
            var smallImage: UIImage? { get }
        #endif
    }

    // MARK: - Dose Types & Entries

    @available(macOS 13.0, iOS 14.0, *) public enum DoseType: String, Codable {
        case basal
        case bolus
        case resume
        case suspend
        case tempBasal

        public var pumpEventType: PumpEventType {
            switch self {
            case .basal: return .basal
            case .bolus: return .bolus
            case .resume: return .resume
            case .suspend: return .suspend
            case .tempBasal: return .tempBasal
            }
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public enum DoseUnit: String, Codable {
        case units
        case unitsPerHour
    }

    @available(macOS 13.0, iOS 14.0, *) public enum InsulinType: String, Codable {
        case novolog
        case humalog
        case apidra
        case fiasp
        case lyumjev
        case afrezza
        case rapidActingAnalog
        case ultraRapidActing
        case ultraRapidInsulin
        case longActing
        case unknown
    }

    @available(macOS 13.0, iOS 14.0, *) public struct DoseEntry: TimelineValue, Equatable, Codable {
        public let type: DoseType
        public var startDate: Date
        public var endDate: Date
        // Internal in real LoopKit too — read doses through programmedUnits/unitsPerHour.
        let value: Double
        public let unit: DoseUnit
        public let decisionId: UUID?
        public let deliveredUnits: Double?
        public let description: String?
        public let insulinType: InsulinType?
        public let automatic: Bool?
        public let manuallyEntered: Bool
        public var syncIdentifier: String?
        public var scheduledBasalRate: LoopQuantity?
        public let isMutable: Bool
        public let wasProgrammedByPumpUI: Bool

        /// Units programmed for delivery (LoopKit parity shim).
        public var programmedUnits: Double {
            switch unit {
            case .units: return value
            case .unitsPerHour: return value * (endDate.timeIntervalSince(startDate) / 3600)
            }
        }

        /// Rate in U/hr (LoopKit parity shim).
        public var unitsPerHour: Double {
            switch unit {
            case .units:
                let hours = endDate.timeIntervalSince(startDate) / 3600
                return hours > 0 ? value / hours : 0
            case .unitsPerHour:
                return value
            }
        }

        private static let minimumMinimedIncrementPerUnit: Double = 20

        /// Delivered units, or programmed units rounded to the Minimed increment (LoopKit parity shim).
        public var unitsInDeliverableIncrements: Double {
            guard case .unitsPerHour = unit else {
                return deliveredUnits ?? programmedUnits
            }
            return deliveredUnits ?? round(programmedUnits * DoseEntry.minimumMinimedIncrementPerUnit) / DoseEntry.minimumMinimedIncrementPerUnit
        }

        /// LoopKit parity shim of InsulinMath's `trimmed`.
        public func trimmed(from start: Date? = nil, to end: Date? = nil, syncIdentifier: String? = nil) -> DoseEntry? {
            guard startDate < end ?? .distantFuture, endDate > start ?? .distantPast else {
                return nil
            }

            let originalDuration = endDate.timeIntervalSince(startDate)
            let startDate = max(start ?? .distantPast, self.startDate)
            let endDate = max(startDate, min(end ?? .distantFuture, self.endDate))

            var trimmedDeliveredUnits: Double? = deliveredUnits
            var trimmedValue: Double = value

            if originalDuration > .ulpOfOne && (startDate > self.startDate || endDate < self.endDate) {
                let updatedActualDelivery = unitsInDeliverableIncrements * (endDate.timeIntervalSince(startDate) / originalDuration)
                if deliveredUnits != nil {
                    trimmedDeliveredUnits = updatedActualDelivery
                }
                if case .units = unit {
                    trimmedValue = updatedActualDelivery
                }
            }

            return DoseEntry(
                type: type,
                startDate: startDate,
                endDate: endDate,
                value: trimmedValue,
                unit: unit,
                decisionId: decisionId,
                deliveredUnits: trimmedDeliveredUnits,
                description: description,
                syncIdentifier: syncIdentifier,
                scheduledBasalRate: scheduledBasalRate,
                insulinType: insulinType,
                automatic: automatic,
                manuallyEntered: manuallyEntered,
                isMutable: isMutable,
                wasProgrammedByPumpUI: wasProgrammedByPumpUI
            )
        }

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
                decisionId: nil,
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
                decisionId: nil,
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
            decisionId: UUID?,
            deliveredUnits: Double? = nil,
            description: String? = nil,
            syncIdentifier: String? = nil,
            scheduledBasalRate: LoopQuantity? = nil,
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
            self.decisionId = decisionId
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(DoseType.self, forKey: .type)
            startDate = try container.decode(Date.self, forKey: .startDate)
            endDate = try container.decode(Date.self, forKey: .endDate)
            value = try container.decode(Double.self, forKey: .value)
            unit = try container.decode(DoseUnit.self, forKey: .unit)
            decisionId = try container.decodeIfPresent(UUID.self, forKey: .decisionId)
            deliveredUnits = try container.decodeIfPresent(Double.self, forKey: .deliveredUnits)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            syncIdentifier = try container.decodeIfPresent(String.self, forKey: .syncIdentifier)
            insulinType = try container.decodeIfPresent(InsulinType.self, forKey: .insulinType)
            if let scheduledBasalRate = try container.decodeIfPresent(Double.self, forKey: .scheduledBasalRate),
               let scheduledBasalRateUnit = try container.decodeIfPresent(String.self, forKey: .scheduledBasalRateUnit),
               let unit = LoopUnit.allCases.first(where: { $0.unitString == scheduledBasalRateUnit })
            {
                self.scheduledBasalRate = LoopQuantity(unit: unit, doubleValue: scheduledBasalRate)
            }
            automatic = try container.decodeIfPresent(Bool.self, forKey: .automatic)
            manuallyEntered = try container.decodeIfPresent(Bool.self, forKey: .manuallyEntered) ?? false
            isMutable = try container.decodeIfPresent(Bool.self, forKey: .isMutable) ?? false
            wasProgrammedByPumpUI = try container.decodeIfPresent(Bool.self, forKey: .wasProgrammedByPumpUI) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(startDate, forKey: .startDate)
            try container.encode(endDate, forKey: .endDate)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
            try container.encodeIfPresent(decisionId, forKey: .decisionId)
            try container.encodeIfPresent(deliveredUnits, forKey: .deliveredUnits)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(syncIdentifier, forKey: .syncIdentifier)
            try container.encodeIfPresent(insulinType, forKey: .insulinType)
            if let scheduledBasalRate = scheduledBasalRate {
                try container.encode(scheduledBasalRate.doubleValue(for: .internationalUnitsPerHour), forKey: .scheduledBasalRate)
                try container.encode(LoopUnit.internationalUnitsPerHour.unitString, forKey: .scheduledBasalRateUnit)
            }
            try container.encodeIfPresent(automatic, forKey: .automatic)
            if manuallyEntered {
                try container.encode(manuallyEntered, forKey: .manuallyEntered)
            }
            if isMutable {
                try container.encode(isMutable, forKey: .isMutable)
            }
            if wasProgrammedByPumpUI {
                try container.encode(wasProgrammedByPumpUI, forKey: .wasProgrammedByPumpUI)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case startDate
            case endDate
            case value
            case unit
            case decisionId
            case deliveredUnits
            case description
            case syncIdentifier
            case scheduledBasalRate
            case scheduledBasalRateUnit
            case insulinType
            case automatic
            case manuallyEntered
            case isMutable
            case wasProgrammedByPumpUI
        }
    }

    // MARK: - Scheduling & Limits

    @available(macOS 13.0, iOS 14.0, *) public struct RepeatingScheduleValue<T>: Codable,
        Equatable where T: Codable & Equatable
    {
        public var startTime: TimeInterval
        public var value: T

        public init(startTime: TimeInterval, value: T) {
            self.startTime = startTime
            self.value = value
        }
    }

    // Failable and sorting, as real LoopKit's DailyValueSchedule is.
    @available(macOS 13.0, iOS 14.0, *) public struct BasalRateSchedule: Codable, Equatable {
        public private(set) var items: [RepeatingScheduleValue<Double>]
        public private(set) var timeZone: TimeZone

        public init?(dailyItems: [RepeatingScheduleValue<Double>], timeZone: TimeZone? = nil) {
            let sorted = dailyItems.sorted { $0.startTime < $1.startTime }
            guard !sorted.isEmpty else { return nil }
            items = sorted
            self.timeZone = timeZone ?? TimeZone.current
        }
    }

    // Only the units TandemKit uses; real LoopKit's LoopUnit has more, and converts between them.
    @available(macOS 13.0, iOS 14.0, *) public enum LoopUnit: Sendable, CaseIterable {
        case internationalUnit
        case internationalUnitsPerHour

        public var unitString: String {
            switch self {
            case .internationalUnit: "IU"
            case .internationalUnitsPerHour: "IU/hr"
            }
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public struct LoopQuantity: Hashable, Equatable, Comparable, Sendable {
        public let unit: LoopUnit
        private let value: Double

        public init(unit: LoopUnit, doubleValue value: Double) {
            self.unit = unit
            self.value = value
        }

        public func doubleValue(for unit: LoopUnit) -> Double {
            guard self.unit == unit else {
                fatalError("Conversion Error: \(self.unit) is not compatible with \(unit).")
            }
            return value
        }

        public static func < (lhs: LoopQuantity, rhs: LoopQuantity) -> Bool {
            lhs.value < rhs.doubleValue(for: lhs.unit)
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public struct DeliveryLimits: Equatable {
        public var maximumBasalRate: LoopQuantity?
        public var maximumBolus: LoopQuantity?

        public init(maximumBasalRate: LoopQuantity?, maximumBolus: LoopQuantity?) {
            self.maximumBasalRate = maximumBasalRate
            self.maximumBolus = maximumBolus
        }
    }

    // MARK: - Reservoir and Events

    @available(macOS 13.0, iOS 14.0, *) public protocol ReservoirValue {
        var startDate: Date { get }
        var unitVolume: Double { get }
    }

    @available(macOS 13.0, iOS 14.0, *) public enum PumpComponent: String, Codable {
        case reservoir
        case pump
        case infusionSet
    }

    @available(macOS 13.0, iOS 14.0, *) public enum PumpEventType: Equatable, Codable {
        case alarm
        case alarmClear
        case basal
        case bolus
        case prime
        case rewind
        case suspend
        case resume
        case tempBasal
        case timeZoneSync(fromSecondsFromGMT: Int, toSecondsFromGMT: Int)
        case replaceComponent(componentType: PumpComponent)
    }

    @available(macOS 13.0, iOS 14.0, *) public struct NewPumpEvent: Codable, Equatable {
        public let date: Date
        public let dose: DoseEntry?
        public let isMutable: Bool
        public let raw: Data
        public let title: String
        public let type: PumpEventType?
        public let alarmType: PumpAlarmType?

        public init(
            date: Date,
            dose: DoseEntry?,
            isMutable: Bool = false,
            raw: Data,
            title: String,
            type: PumpEventType? = nil,
            alarmType: PumpAlarmType? = nil
        ) {
            self.date = date
            // As in LoopKit: the dose takes the event's raw as its identity, and lends its type.
            var dose = dose
            dose?.syncIdentifier = raw.map { String(format: "%02hhx", $0) }.joined()
            self.dose = dose
            self.isMutable = isMutable
            self.raw = raw
            self.title = title
            self.type = type ?? dose?.type.pumpEventType
            self.alarmType = alarmType
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public enum PumpAlarmType: Equatable, Codable {
        case autoOff
        case lowInsulin
        case lowPower
        case noDelivery
        case noInsulin
        case noPower
        case occlusion
        case other(_ details: String)
    }

    // MARK: - Errors & Activation

    @available(macOS 13.0, iOS 14.0, *) public enum PumpManagerError: Error {
        case configuration(Error?)
        case connection(Error?)
        case communication(Error?)
        case deviceState(Error?)
        case uncertainDelivery
    }

    @available(macOS 13.0, iOS 14.0, *) public enum BolusActivationType: String, Codable {
        case automatic
        case manualNoRecommendation
        case manualRecommendationAccepted
        case manualRecommendationChanged
        case none

        public var isAutomatic: Bool {
            self == .automatic
        }
    }

    // MARK: - Alerts

    @available(macOS 13.0, iOS 14.0, *) public struct Alert: Equatable {
        public typealias AlertIdentifier = String

        public struct Identifier: Equatable, Hashable {
            public let managerIdentifier: String
            public let alertIdentifier: AlertIdentifier

            public init(managerIdentifier: String, alertIdentifier: AlertIdentifier) {
                self.managerIdentifier = managerIdentifier
                self.alertIdentifier = alertIdentifier
            }

            public var value: String { "\(managerIdentifier).\(alertIdentifier)" }
        }

        public struct Content: Equatable {
            public let title: String
            public let body: String
            public let acknowledgeActionButtonLabel: String

            public init(title: String, body: String, acknowledgeActionButtonLabel: String) {
                self.title = title
                self.body = body
                self.acknowledgeActionButtonLabel = acknowledgeActionButtonLabel
            }
        }

        public enum Trigger: Equatable {
            case immediate
            case delayed(interval: TimeInterval)
            case repeating(repeatInterval: TimeInterval)
        }

        public enum InterruptionLevel: String, Equatable, Codable {
            case passive
            case active
            case timeSensitive
            case critical
        }

        public struct Sound: Equatable {
            public let name: String
            public init(name: String) { self.name = name }
            public static let vibrate = Sound(name: "vibrate")
        }

        public let identifier: Identifier
        public let foregroundContent: Content?
        public let backgroundContent: Content?
        public let trigger: Trigger
        public let interruptionLevel: InterruptionLevel

        public init(
            identifier: Identifier,
            foregroundContent: Content?,
            backgroundContent: Content?,
            trigger: Trigger,
            interruptionLevel: InterruptionLevel = .timeSensitive
        ) {
            self.identifier = identifier
            self.foregroundContent = foregroundContent
            self.backgroundContent = backgroundContent
            self.trigger = trigger
            self.interruptionLevel = interruptionLevel
        }
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol AlertResponder: AnyObject {
        func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) async throws
        func handleAlertAction(actionIdentifier: String, from alert: Alert) async throws
    }

    @available(macOS 13.0, iOS 14.0, *) extension AlertResponder {
        public func handleAlertAction(actionIdentifier: String, from alert: Alert) async throws {}
    }

    @available(macOS 13.0, iOS 14.0, *) public protocol AlertSoundVendor {
        func getSoundBaseURL() -> URL?
        func getSounds() -> [Alert.Sound]
    }

    @available(macOS 13.0, iOS 14.0, *) public struct PersistedAlert: Equatable {
        public let alert: Alert
        public let issuedDate: Date
        public let retractedDate: Date?
        public let acknowledgedDate: Date?

        public init(alert: Alert, issuedDate: Date, retractedDate: Date?, acknowledgedDate: Date?) {
            self.alert = alert
            self.issuedDate = issuedDate
            self.retractedDate = retractedDate
            self.acknowledgedDate = acknowledgedDate
        }
    }

    // MARK: - Plugins

    public protocol Pluggable: AnyObject {
        static var pluginIdentifier: String { get }
        var pluginIdentifier: String { get }
        func initializationComplete(for pluggables: [Pluggable])
    }

    public extension Pluggable {
        var pluginIdentifier: String { type(of: self).pluginIdentifier }
        func initializationComplete(for _: [Pluggable]) {}
    }

    // MARK: - Dose Progress Observation

    @available(macOS 13.0, iOS 14.0, *) public protocol DoseProgressObserver: AnyObject {
        func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter)
    }

    // MARK: - Weak Collections
    //
    // Ported from loopandlearn/LoopKit @ 0229bb18. Callbacks must stay async:
    // a synchronous notify deadlocks when a delegate re-enters the manager.

    public struct Weak<Value> {
        private weak var _value: AnyObject?

        public var value: Value? { _value as? Value }

        public init(_ value: Value) {
            precondition(
                Mirror(reflecting: value).displayStyle == .class,
                "Weak references can only be held of class types."
            )
            _value = value as AnyObject
        }
    }

    public struct WeakSet<Element>: Sequence {
        private var storage: [ObjectIdentifier: Weak<Element>] = [:]

        public init() {}

        public var isEmpty: Bool { storage.values.allSatisfy { $0.value == nil } }

        public func contains(_ member: Element) -> Bool {
            storage[ObjectIdentifier(member as AnyObject)]?.value != nil
        }

        @discardableResult
        public mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
            let id = ObjectIdentifier(newMember as AnyObject)
            if let existing = storage[id]?.value {
                return (inserted: false, memberAfterInsert: existing)
            }
            storage[id] = Weak(newMember)
            return (inserted: true, memberAfterInsert: newMember)
        }

        @discardableResult
        public mutating func remove(_ member: Element) -> Element? {
            storage.removeValue(forKey: ObjectIdentifier(member as AnyObject))?.value
        }

        public mutating func cleanupDeallocatedElements() {
            storage = storage.filter { $0.value.value != nil }
        }

        public func makeIterator() -> AnyIterator<Element> {
            AnyIterator(storage.values.compactMap(\.value).makeIterator())
        }
    }

    /// Observers called back on the queue each registered with.
    public final class WeakSynchronizedSet<Element> {
        private struct Container {
            weak var element: AnyObject?
            let queue: DispatchQueue

            func call(_ body: @escaping (Element) -> Void) {
                guard let element = element as? Element else { return }
                queue.async { body(element) }
            }
        }

        private var storage: [ObjectIdentifier: Container] = [:]
        private let lock = NSLock()

        public init() {}

        public func insert(_ element: Element, queue: DispatchQueue) {
            let id = ObjectIdentifier(element as AnyObject)
            lock.lock()
            defer { lock.unlock() }
            storage[id] = Container(element: element as AnyObject, queue: queue)
        }

        public func contains(_ element: Element) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return storage[ObjectIdentifier(element as AnyObject)] != nil
        }

        public func removeElement(_ element: Element) {
            lock.lock()
            defer { lock.unlock() }
            storage.removeValue(forKey: ObjectIdentifier(element as AnyObject))
        }

        @discardableResult
        public func cleanupDeallocatedElements() -> Self {
            lock.lock()
            defer { lock.unlock() }
            storage = storage.filter { $0.value.element != nil }
            return self
        }

        // Lock held while iterating; each call is dispatched out.
        public func forEach(_ body: @escaping (Element) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            for container in storage.values {
                container.call(body)
            }
        }
    }

    public final class WeakSynchronizedDelegate<Delegate> {
        private weak var _delegate: AnyObject?
        private var _queue: DispatchQueue
        private let lock = NSLock()

        public init(queue: DispatchQueue = .main) {
            _queue = queue
        }

        public var delegate: Delegate? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _delegate as? Delegate
            }
            set {
                lock.lock()
                _delegate = newValue as AnyObject?
                lock.unlock()
            }
        }

        public var queue: DispatchQueue! {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _queue
            }
            set {
                lock.lock()
                _queue = newValue ?? .main
                lock.unlock()
            }
        }

        private func currentDelegateAndQueue() -> (Delegate?, DispatchQueue) {
            lock.lock()
            defer { lock.unlock() }
            return (_delegate as? Delegate, _queue)
        }

        /// Async: `block` has not necessarily run when this returns.
        public func notify(_ block: @escaping (Delegate?) -> Void) {
            let (delegate, queue) = currentDelegateAndQueue()
            queue.async { block(delegate) }
        }

        public func notifyDelayed(by interval: TimeInterval, _ block: @escaping (Delegate?) -> Void) {
            let (delegate, queue) = currentDelegateAndQueue()
            queue.asyncAfter(deadline: .now() + interval) { block(delegate) }
        }

        public func call<ReturnType>(_ block: (Delegate?) -> ReturnType) -> ReturnType {
            lock.lock()
            defer { lock.unlock() }
            var result: ReturnType!
            _queue.sync {
                result = block(_delegate as? Delegate)
            }
            return result
        }
    }

    // MARK: - CGM Manager

    public protocol CGMManagerUI {}
#endif
