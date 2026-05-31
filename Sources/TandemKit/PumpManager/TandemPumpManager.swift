import Combine
import CoreBluetooth
import Dispatch
import Foundation
import HealthKit
import LoopKit
import UIKit

public class TandemPumpManager: PumpManager, Pluggable {
    public static var pluginIdentifier: String = "TandemPumpManager"

    public var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    public typealias RawStateValue = [String: Any]

    let bluetooth: TandemBluetoothManager

    // Tandem Mobi and t:slim X2: max 16 basal segments within a profile
    public static var onboardingMaximumBasalScheduleEntryCount: Int = 16

    // Tandem Mobi and t:slim X2: 0.0u, then 0.1 - 15.00u/hr in 0.01u chunks
    public static var onboardingSupportedBasalRates: [Double] = [0.0] + strideRange(from: 0.1, through: 15.0, by: 0.01)

    // Tandem Mobi and t:slim X2: 0.05 - 25.00 unit bolus in 0.05u chunks
    public static var onboardingSupportedBolusVolumes: [Double] = strideRange(from: 0.05, through: 25.0, by: 0.05)

    public static var onboardingSupportedMaximumBolusVolumes: [Double] = strideRange(from: 0.05, through: 25.0, by: 0.01)

    internal let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private var oldState: TandemPumpManagerState
    public var state: TandemPumpManagerState
    internal let logger = TandemLogger(category: "TandemPumpManager")
    internal let telemetryScheduler = PumpTelemetryScheduler(label: "com.loopkit.TandemKit.TelemetryScheduler")

    // Status tracking
    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()

    // Stream message publishers
    public let fillTubingStateStream = PassthroughSubject<FillTubingStateStreamResponse, Never>()
    private let sessionInitializationQueue = DispatchQueue(label: "com.jwoglom.TandemKit.sessionInit")
    internal var bolusProgressReport: TandemDoseProgressReporter?
    private let silentToneManager = TandemSilentToneManager()
    var notificationBundle = NotificationBundle()

    // BLE heartbeat propagation (LoopKit PumpManager protocol)
    private var provideHeartbeat: Bool = false
    private var lastHeartbeat: Date = .distantPast

    @objc func appMovedToBackground() {
        if state.useSilentTones {
            logger.info("Starting silent tones")
            silentToneManager.startBackgroundTask()
        }
    }

    @objc func appMovedToForeground() {
        silentToneManager.stopBackgroundTask()
    }

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    private static func makeStatus(from state: TandemPumpManagerState) -> PumpManagerStatus {
        PumpManagerStatus(
            timeZone: TimeZone.current,
            device: state.deviceInfo,
            pumpBatteryChargeRemaining: state.lastBatteryReading?.chargeRemaining,
            basalDeliveryState: state.basalDeliveryState,
            bolusState: state.bolusState,
            insulinType: state.insulinType,
            deliveryIsUncertain: false
        )
    }

    public init(state: TandemPumpManagerState) {
        self.state = state
        oldState = TandemPumpManagerState(rawValue: state.rawValue)
        bluetooth = TandemBluetoothManager()
        bluetooth.pumpManager = self

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    public required convenience init?(rawState: RawStateValue) {
        self.init(state: TandemPumpManagerState(rawValue: rawState))
    }

    public var rawState: RawStateValue {
        state.rawValue
    }

    public var status: PumpManagerStatus {
        TandemPumpManager.makeStatus(from: state)
    }

    public var debugDescription: String {
        "TandemPumpManager(state: \(state))"
    }

    public var isOnboarded: Bool {
        state.pumpState.derivedSecret != nil
    }

    private var hasPairedPumpState: Bool {
        state.pumpState.valid
    }

    // MARK: - Pump Capabilities

    public var supportedBasalRates: [Double] {
        TandemPumpManager.onboardingSupportedBasalRates
    }

    public var supportedBolusVolumes: [Double] {
        TandemPumpManager.onboardingSupportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        supportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        TandemPumpManager.onboardingMaximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        .minutes(10)
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        false
    }

    public var pumpReservoirCapacity: Double {
        200 // Tandem mobi reservoir capacity in units. t:slim X2 is 300
    }

    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // We do support rounding a 0 U volume to 0
        supportedBolusVolumes.last(where: { $0 <= units }) ?? 0
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        supportedBasalRates.last(where: { $0 <= unitsPerHour }) ?? 0
    }

    public var lastSync: Date? {
        state.lastReconciliation
    }

    public var reservoirLevel: ReservoirValue? {
        state.lastReservoirReading
    }

    public var autoAcknowledgeBasalAlerts: Bool {
        state.autoAcknowledgeBasalAlerts
    }

    internal func notifyDelegateStateUpdated() {
        let status = TandemPumpManager.makeStatus(from: state)
        let oldStatus = TandemPumpManager.makeStatus(from: oldState)

        if let delegate = pumpManagerDelegate {
            pumpDelegate.queue.async { [weak self] in
                guard let self = self else { return }

                delegate.pumpManagerDidUpdateState(self)
                delegate.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }
        }

        statusObservers.forEach { observer in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }

        oldState = TandemPumpManagerState(rawValue: state.rawValue)
    }

    // MARK: - Status Observers

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    private func notifyPumpManagerDelegateOfError(_ error: PumpCommError) {
        guard let delegate = pumpManagerDelegate, let queue = delegateQueue else { return }
        queue.async {
            delegate.pumpManager(self, didError: PumpManagerError.communication(error))
        }
    }

    private func percentForTempBasal(requestedRate: Double, baseline: Double) -> Int {
        guard baseline > 0 else { return 0 }
        let percent = Int((requestedRate / baseline * 100.0).rounded())
        return max(0, min(percent, 250))
    }

    // MARK: - Basic Pump Manager Interface

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get {
            pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }

    public func configureAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        state.autoAcknowledgeBasalAlerts = enabled
        notifyDelegateStateUpdated()

        logger.info("Auto-acknowledge basal alerts \(enabled ? "enabled" : "disabled")")
    }

    public func configureSilentMode(_ enabled: Bool) {
        state.useSilentTones = enabled
        notifyDelegateStateUpdated()

        logger.info("Heartbeat mode silent tones \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sync: \(error.localizedDescription)")
                completion?(self.state.lastReconciliation)
                return
            }

            self.fetchDeliveryLimits()
            self.fetchReservoirStatus()
            self.fetchBatteryStatus()
            self.fetchBolusStatus()
            self.fetchHomeScreenStatus()
            self.fetchControlIQStatus()
            self.fetchNotificationCount()
            self.fetchTimeSinceReset()
            self.fetchGlobalPumpSettings()

            self.state.lastReconciliation = Date.now
            self.notifyDelegateStateUpdated()

            completion?(self.state.lastReconciliation)
        }
    }

    private static let lastHeartbeatDebounceInterval: TimeInterval = 10

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        provideHeartbeat = mustProvideBLEHeartbeat
    }

    /// Query the delegate to determine whether heartbeats should be enabled.
    /// Must not be called on the delegate's queue.
    private func updateBLEHeartbeatPreference() {
        pumpDelegate.notify { delegate in
            self.provideHeartbeat = delegate?.pumpManagerMustProvideBLEHeartbeat(self) == true
        }
    }

    private func updateLastHeartbeatIfNeeded() {
        if provideHeartbeat, Date().timeIntervalSince(lastHeartbeat) > Self.lastHeartbeatDebounceInterval {
            pumpDelegate.notify { delegate in
                delegate?.pumpManagerBLEHeartbeatDidFire(self)
            }
            lastHeartbeat = Date()
        }
    }

    public func createBolusProgressReporter(reportingOn _: DispatchQueue) -> DoseProgressReporter? {
        bolusProgressReport
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        if units < 10 {
            units / TandemDoseProgressReporter.BOLUS_SPEED_UNDER_10U
        } else {
            units / TandemDoseProgressReporter.BOLUS_SPEED_OVER_10U
        }
    }

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        logger.info("Enacting bolus - units \(units)U")

        if state.useControlIQ, activationType.isAutomatic {
            logger.warning("[enactBolus] Blocked automatic bolus: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for bolus: \(error.localizedDescription)")
                completion(.communication(PumpCommError.pumpNotConnected))
                return
            }

            guard let permissionResponse = self.bluetooth.write(
                message: BolusPermissionRequest(),
                expecting: BolusPermissionResponse.self
            ) as? BolusPermissionResponse else {
                self.logger.error("Failed to request bolus permission")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard permissionResponse.isPermissionGranted else {
                self.logger.error("Pump rejected bolus permission request")
                completion(.communication(PumpCommError.invalidPacket))
                return
            }

            let milliUnits = max(0, Int((units * 1000).rounded()))
            let totalVolume = UInt32(clamping: milliUnits)

            let bolusRequest = InitiateBolusRequest(
                totalVolume: totalVolume,
                bolusID: permissionResponse.bolusId,
                bolusTypeBitmask: BolusType.toBitmask([.food2]),
                foodVolume: totalVolume,
                correctionVolume: 0,
                bolusCarbs: 0,
                bolusBG: 0,
                bolusIOB: 0
            )
            guard let initiateResponse = self.bluetooth.write(
                message: bolusRequest,
                expecting: InitiateBolusResponse.self
            ) as? InitiateBolusResponse else {
                self.logger.error("Failed to initiate bolus")
                self.releaseBolusPermission(bolusId: permissionResponse.bolusId)
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard initiateResponse.wasBolusInitiated else {
                self.logger.error("Bolus was not initiated")
                self.releaseBolusPermission(bolusId: permissionResponse.bolusId)
                completion(.communication(PumpCommError.invalidPacket))
                return
            }

            let dose = UnfinalizedDose(
                units: units,
                // 5s needed before bolus enacting is started
                duration: self.estimatedDuration(toBolus: units) + .seconds(5),
                activationType: activationType,
                insulinType: self.state.insulinType,
                bolusId: permissionResponse.bolusId
            )

            let doseEntry = dose.toDoseEntry()
            self.bolusProgressReport = TandemDoseProgressReporter(
                pumpManager: self,
                dose: doseEntry,
                activationType: activationType
            )
            self.telemetryScheduler.schedule(kind: .bolus, interval: .seconds(1), leeway: .seconds(0.5)) {
                self.fetchBolusStatus()
            }

            self.state.bolusDose = dose
            self.state.bolusState = .initiating
            self.state.lastReconciliation = Date.now
            self.notifyDelegateStateUpdated()
            self.emitPumpEvents([NewPumpEvent.bolus(dose: doseEntry, units: units)], replacePendingEvents: false)

            completion(nil)
        }
    }

    public func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void) {
        logger.info("Cancelling bolus...")

        guard let bolusDose = state.bolusDose, let bolusId = bolusDose.bolusId else {
            logger.error("No active bolus...")
            completion(.failure(.communication(PumpCommError.noActiveBolus)))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for cancel bolus: \(error.localizedDescription)")
                completion(.failure(.communication(PumpCommError.pumpNotConnected)))
                return
            }

            guard let response = self.bluetooth.write(
                message: CancelBolusRequest(bolusId: bolusId),
                expecting: CancelBolusResponse.self
            ) as? CancelBolusResponse else {
                self.logger.error("Failed to cancel bolus")
                completion(.failure(.communication(PumpCommError.noResponse)))
                return
            }

            guard response.wasCancelled else {
                self.logger.error("Pump failed to cancel bolus")
                completion(.failure(.communication(PumpCommError.invalidPacket)))
                return
            }

            // Allow the Mobi to store the bolus in storage
            Thread.sleep(forTimeInterval: .seconds(2))

            // Query the pump for the actual delivered volume before clearing state
            bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0

            let canceledDose = bolusDose.toDoseEntry(endDate: Date.now)

            // Clean up bolus tracking state (mirrors handleBolusResponse completion path)
            self.telemetryScheduler.cancelAll()
            self.bolusProgressReport = nil
            self.state.bolusDose = nil

            var events = self.getActivePumpEvents()
            events
                .append(
                    NewPumpEvent
                        .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, date: canceledDose.startDate)
                )

            self.state.lastReconciliation = Date.now
            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            completion(.success(nil))
        }
    }

    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        logger.info("Setting temp basal at \(unitsPerHour)U/hr for \(duration)s")
        guard !state.useControlIQ else {
            logger.warning("[enactTempBasal] Blocked: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        let baselineRate = getScheduledBasalRate()
        guard baselineRate > 0 else {
            logger.error("No scheduled basal rate present or is 0, cannot enact temp basal")
            completion(.deviceState(PumpCommError.invalidScheduledBasalRate))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for temp basal: \(error.localizedDescription)")
                completion(.connection(PumpCommError.pumpNotConnected))
                return
            }

            guard let currentTempRate = self.bluetooth.write(
                message: TempRateRequest(),
                expecting: TempRateResponse.self
            ) as? TempRateResponse else {
                self.logger.error("Failed to fetch current temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            if currentTempRate.active {
                guard let stopCurrentRate = self.bluetooth.write(
                    message: StopTempRateRequest(),
                    expecting: StopTempRateResponse.self
                ) as? StopTempRateResponse else {
                    self.logger.error("Failed to stop temp rate")
                    completion(.communication(PumpCommError.noResponse))
                    return
                }

                guard stopCurrentRate.isStatusOK else {
                    self.logger.error("Failed to stop temp rate - Status: \(stopCurrentRate.status)")
                    completion(.communication(PumpCommError.invalidPacket))
                    return
                }
            }

            let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)
            let absoluteRate = self
                .roundToSupportedBasalRate(unitsPerHour: Double(baselineRate * (Double(percent) / 100)))

            if duration < .ulpOfOne || percent == 100 {
                // We only needed to cancel any current temp basal
                // Qualifying events will handle state update
                completion(nil)
                return
            }

            let request = SetTempRateRequest(minutes: Int(duration.minutes), percent: percent)
            guard let response = self.bluetooth.write(
                message: request,
                expecting: SetTempRateResponse.self
            ) as? SetTempRateResponse else {
                self.logger.error("Failed to set temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to set temp rate - Status: \(response.status)")
                completion(.communication(PumpCommError.invalidPacket))
                return
            }

            let dose = UnfinalizedDose(
                tempRate: absoluteRate,
                duration: duration,
                automatic: true,
                insulinType: self.state.insulinType,
            )
            var events = self.getActivePumpEvents(endDate: dose.startDate)
            events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(), date: dose.startDate))

            self.state.basalDose = dose
            self.state.lastReconciliation = dose.startDate

            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            self.logger.info("Temp basal enacted!")
            completion(nil)
        }
    }

    public func suspendDelivery(completion: @escaping (_ error: Error?) -> Void) {
        logger.info("Suspend Insulin Delivery...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }

            guard let currentTempResponse = self.bluetooth.write(
                message: TempRateRequest(),
                expecting: TempRateResponse.self
            ) as? TempRateResponse else {
                self.logger.error("Failed to get currentTempRate...")
                completion(PumpCommError.noResponse)
                return
            }
            if currentTempResponse.active {
                _ = self.bluetooth.write(message: StopTempRateRequest(), expecting: StopTempRateRequest.self)
            }

            let response = self.bluetooth.write(
                message: SuspendPumpingRequest(),
                expecting: SuspendPumpingResponse.self
            ) as? SuspendPumpingResponse
            guard let response, response.status == 0 else {
                self.logger.error("Failed to Suspend delivery - Status: \(response?.status ?? -1)")
                completion(PumpCommError.noResponse)
                return
            }

            let suspendDose = UnfinalizedDose(suspendStartTime: Date.now)
            var events = self.getActivePumpEvents(endDate: suspendDose.startDate)
            events.append(NewPumpEvent.suspend(dose: suspendDose.toDoseEntry(), date: suspendDose.startDate))

            self.state.basalDose = suspendDose
            self.state.lastReconciliation = Date.now

            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            self.logger.info("Insulin Delivery Suspended!")
            completion(nil)
        }
    }

    public func resumeDelivery(completion: @escaping (_ error: Error?) -> Void) {
        logger.info("Resume Insulin Delivery...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }

            let response = self.bluetooth.write(
                message: ResumePumpingRequest(),
                expecting: ResumePumpingResponse.self
            ) as? ResumePumpingResponse
            guard let response, response.status == 0 else {
                self.logger.error("Failed to Resume delivery - Status: \(response?.status ?? -1)")
                completion(PumpCommError.noResponse)
                return
            }

            let dose = UnfinalizedDose(
                resumeStartTime: Date.now,
                insulinType: self.state.insulinType
            )
            let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]

            self.state.basalDose = dose
            self.state.lastReconciliation = Date.now

            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            self.logger.info("Insulin Delivery Resumed!")
            completion(nil)
        }
    }

    public func syncDeliveryLimits(
        limits: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    ) {
        logger.info("syncDeliveryLimits...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sync delivery limits: \(error.localizedDescription)")
                completion(.failure(PumpCommError.pumpNotConnected))
                return
            }

            let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())

            if let maxBasal = limits.maximumBasalRate?.doubleValue(for: hkUnit) {
                let milliunits = Int((maxBasal * 1000.0).rounded())
                guard let basalResponse = self.bluetooth.write(
                    message: SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits),
                    expecting: SetMaxBasalLimitResponse.self
                ) as? SetMaxBasalLimitResponse else {
                    self.logger.error("Failed to set maxBasalLimit")
                    completion(.failure(PumpCommError.invalidPacket))
                    return
                }

                guard basalResponse.isStatusOK else {
                    self.logger.error("Failed to set maxBasalLimit - Status: \(basalResponse.status)")
                    completion(.failure(PumpCommError.invalidPacket))
                    return
                }
            }

            if let maxBolus = limits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit()) {
                let milliunits = Int((maxBolus * 1000.0).rounded())

                guard let bolusResponse = self.bluetooth.write(
                    message: SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits),
                    expecting: SetMaxBolusLimitResponse.self
                ) as? SetMaxBolusLimitResponse else {
                    self.logger.error("Failed to set maxBolusLimit")
                    completion(.failure(PumpCommError.invalidPacket))
                    return
                }

                guard bolusResponse.isStatusOK else {
                    self.logger.error("Failed to set maxBolusLimit - Status: \(bolusResponse.status)")
                    completion(.failure(PumpCommError.invalidPacket))
                    return
                }
            }

            self.state.settings.maxTempBasalRate = limits.maximumBasalRate?.doubleValue(for: hkUnit)
            self.state.settings.maxBolus = limits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit())
            self.notifyDelegateStateUpdated()

            completion(.success(limits))
        }
    }

    func enterChangeCartridgeMode(completion: @escaping (EnterChangeCartridgeModeResponse?) -> Void) {
        logger.info("Entering cartridge change mode")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: EnterChangeCartridgeModeRequest(),
                expecting: EnterChangeCartridgeModeResponse.self
            ) as? EnterChangeCartridgeModeResponse

            completion(response)
        }
    }

    func exitChangeCartridgeMode(completion: @escaping (ExitChangeCartridgeModeResponse?) -> Void) {
        logger.info("Exiting cartridge change mode")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: ExitChangeCartridgeModeRequest(),
                expecting: ExitChangeCartridgeModeResponse.self
            ) as? ExitChangeCartridgeModeResponse

            completion(response)
        }
    }

    func enterFillTubingMode(completion: @escaping (EnterFillTubingModeResponse?) -> Void) {
        logger.info("Entering tube filling mode")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: EnterFillTubingModeRequest(),
                expecting: EnterFillTubingModeResponse.self
            ) as? EnterFillTubingModeResponse

            completion(response)
        }
    }

    func exitFillTubingMode(completion: @escaping (ExitFillTubingModeResponse?) -> Void) {
        logger.info("Exiting tube filling mode")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: ExitFillTubingModeRequest(),
                expecting: ExitFillTubingModeResponse.self
            ) as? ExitFillTubingModeResponse

            completion(response)
        }
    }

    func primeCanulla(amount: Double, completion: @escaping (FillCannulaResponse?) -> Void) {
        logger.info("Priming canulla - \(amount)U")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: FillCannulaRequest(primeSizeMilliUnits: Int(amount * 1000)),
                expecting: FillCannulaResponse.self
            ) as? FillCannulaResponse

            completion(response)
        }
    }

    public func syncPumpTime(completion: @escaping (Result<Void, PumpManagerError>) -> Void) {
        logger.info("Syncing pump time")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change datetime: \(error.localizedDescription)")
                completion(.failure(PumpManagerError.communication(PumpCommError.pumpNotConnected)))
                return
            }

            let epoch = Dates.fromInstantToJan12008EpochSeconds(Date.now)

            let request = ChangeTimeDateRequest(tandemEpochTime: UInt32(epoch))
            guard let response = self.bluetooth.write(
                message: request,
                expecting: ChangeTimeDateResponse.self
            ) as? ChangeTimeDateResponse else {
                self.logger.error("Failed to change datetime")
                completion(.failure(PumpManagerError.communication(PumpCommError.invalidPacket)))
                return
            }

            if !response.isStatusOK {
                let error = PumpCommError.errorResponse(
                    context: String(
                        localized: "Error syncing time with pump",
                        comment: "Message when pump rejects ChangeTimeDateRequest"
                    ),
                    request: request,
                    response: response
                )
                completion(.failure(PumpManagerError.communication(error)))

            } else {
                completion(.success(()))
            }
        }
    }

    func pairPump(code: String, peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        state.pumpState.pincode = code
        bluetooth.connect(peripheral, completion: completion)
    }

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        logger.debug("Preparing for pump deactivation – tearing down transport")
        bluetooth.disconnect()

        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }

    func setPumpSound(request: SetPumpSoundsRequest, completion: @escaping () -> Void) {
        logger.info("Setting pump sounds...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sound settings: \(error.localizedDescription)")
                completion()
                return
            }

            _ = self.bluetooth.write(message: request, expecting: SetPumpSoundsResponse.self)

            // Allow the patch to set values
            Thread.sleep(forTimeInterval: .seconds(1))
            self.fetchGlobalPumpSettings()

            completion()
        }
    }

    func playSound(completion: @escaping () -> Void) {
        logger.info("Play pump sound...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for play sound: \(error.localizedDescription)")
                completion()
                return
            }

            _ = self.bluetooth.write(message: PlaySoundRequest(), expecting: PlaySoundResponse.self)
            completion()
        }
    }

    func setAlertSnooze(enabled: Bool, durationMins: Int, completion: @escaping (Bool) -> Void) {
        logger.info("Setting alert snooze...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for alert snooze: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: SetPumpAlertSnoozeRequest(snoozeEnabled: enabled, snoozeDurationMins: durationMins),
                expecting: SetPumpAlertSnoozeResponse.self
            ) as? SetPumpAlertSnoozeResponse else {
                self.logger.error("Failed to set alert snooze")
                completion(false)
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to set alert snooze: status \(response.status)")
                completion(false)
                return
            }

            self.state.alertSnoozeEnabled = enabled
            self.state.alertSnoozeDuration = TimeInterval(minutes: Double(durationMins))
            self.notifyDelegateStateUpdated()

            self.logger.info("Alert snooze set: enabled=\(enabled), duration=\(durationMins)m")
            completion(true)
        }
    }

    // MARK: - Quick Bolus Settings

    func setQuickBolusSettings(
        enabled: Bool,
        mode: QuickBolusMode,
        increment: QuickBolusIncrement,
        completion: @escaping (Bool) -> Void
    ) {
        logger.info("Setting quick bolus...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for quick bolus: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: SetQuickBolusSettingsRequest(enabled: enabled, mode: mode, increment: increment),
                expecting: SetQuickBolusSettingsResponse.self
            ) as? SetQuickBolusSettingsResponse else {
                self.logger.error("Failed to set quick bolus")
                completion(false)
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to set quick bolus: status \(response.status)")
                completion(false)
                return
            }

            Thread.sleep(forTimeInterval: .seconds(1))
            self.fetchGlobalPumpSettings()

            completion(true)
        }
    }

    func getControlIQData(completion: @escaping (ControlIQInfoV2Response?, ControlIQSleepScheduleResponse?) -> Void) {
        logger.info("Getting controlIQ info")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for getting controlIQ data: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }

            let iqInfo = self.bluetooth.write(
                message: ControlIQInfoV2Request(),
                expecting: ControlIQInfoV2Response.self
            ) as? ControlIQInfoV2Response

            let scheduleInfo = self.bluetooth.write(
                message: ControlIQSleepScheduleRequest(),
                expecting: ControlIQSleepScheduleResponse.self
            ) as? ControlIQSleepScheduleResponse

            completion(iqInfo, scheduleInfo)
        }
    }

    func setControlIQMode(mode: SetModesRequest.ModeCommand, completion: @escaping (Bool) -> Void) {
        logger.info("Configure controlIQ mode - mode: \(mode)")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for controlIQ mode: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: SetModesRequest(command: mode),
                expecting: SetModesResponse.self
            ) as? SetModesResponse else {
                self.logger.error("Failed to set controlIQ mode")
                completion(false)
                return
            }

            completion(response.isStatusOK)
        }
    }

    func configureControlIQMode(
        _ request: ChangeControlIQSettingsRequest,
        completion: @escaping (Bool, CGMStatusV2Response?) -> Void
    ) {
        logger.info("Configure controlIQ mode: \(request.enabled)")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for controlIQ mode: \(error.localizedDescription)")
                completion(false, nil)
                return
            }

            if request.enabled, self.state.basalDose.type == .tempBasal {
                _ = self.bluetooth.write(message: StopTempRateRequest(), expecting: StopTempRateResponse.self)

                let dose = UnfinalizedDose(
                    basalRate: self.getScheduledBasalRate(),
                    insulinType: self.state.insulinType,
                    startDate: Date.now
                )
                var events = self.getActivePumpEvents(endDate: dose.startDate)
                events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))

                self.state.basalDose = dose
                self.state.lastReconciliation = Date.now
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)
            }

            guard let response = self.bluetooth.write(
                message: request,
                expecting: ChangeControlIQSettingsResponse.self
            ) as? ChangeControlIQSettingsResponse else {
                self.logger.error("Failed to change controlIQ mode")
                completion(false, nil)
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to change controlIQ mode - Status: \(response.status)")
                completion(false, nil)
                return
            }

            let cgmResponse = self.bluetooth.write(
                message: CGMStatusV2Request(),
                expecting: CGMStatusV2Response.self
            ) as? CGMStatusV2Response

            // Pump accepted -- update local preference
            self.state.useControlIQ = request.enabled
            self.state.controlIQWeight = request.weightLbs
            self.state.controlIQTotalDailyInsulin = request.totalDailyInsulinUnits
            self.notifyDelegateStateUpdated()

            self.logger.info("Algorithm mode set to \(request.enabled ? "Control-IQ" : "DIY")")

            // Refresh pump state to confirm ControlIQ status
            Thread.sleep(forTimeInterval: 1.0)
            self.ensureCurrentPumpData { _ in
                completion(true, cgmResponse)
            }
        }
    }

    func setSleepSchedule(
        slot: Int,
        schedule: ControlIQSleepScheduleResponse.SleepSchedule,
        completion: @escaping (Bool) -> Void
    ) {
        logger.info("Setting sleep schedule")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sleep schedule: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: SetSleepScheduleRequest(
                    slot: slot,
                    schedule: schedule,
                    flag: 1
                ),
                expecting: SetSleepScheduleResponse.self
            ) as? SetSleepScheduleResponse else {
                self.logger.error("Failed to set sleep schedule")
                completion(false)
                return
            }

            if !response.isStatusOK {
                self.logger.error("Failed to set sleep schedule - Status: \(response.status)")
            }

            completion(response.isStatusOK)
        }
    }

    func dismissNotification(notification item: NotificationItem, completion: @escaping (Bool) -> Void) {
        logger.info("Dismissing notification - type: \(item.type)")

        guard let dismissType = item.type.dismissType else {
            logger.error("Cannot dismiss notification of type \(item.type)")
            completion(false)
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for dismiss notification: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: DismissNotificationRequest(
                    notificationType: dismissType,
                    notificationId: item.notificationId
                ),
                expecting: DismissNotificationResponse.self
            ) as? DismissNotificationResponse else {
                self.logger.error("Failed to dismiss notification")
                completion(false)
                return
            }

            if !response.isStatusOK {
                self.logger.error("Failed to dismiss notification - Status: \(response.status)")
            }
            completion(response.isStatusOK)
        }
    }

    func getCGMStatus(completion: @escaping (CGMStatusV2Response?) -> Void) {
        logger.info("Fetching CGM status...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for CGM status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(
                message: CGMStatusV2Request(),
                expecting: CGMStatusV2Response.self
            ) as? CGMStatusV2Response

            completion(response)
        }
    }

    func stopCGMSensor(completion: @escaping (Bool) -> Void) {
        logger.info("Stopping CGM Session")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for CGM status: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(
                message: StopDexcomCGMSensorSessionRequest(),
                expecting: StopDexcomCGMSensorSessionResponse.self
            ) as? StopDexcomCGMSensorSessionResponse else {
                self.logger.error("Failed to stop CGM session")
                completion(false)
                return
            }

            completion(response.isStatusOK)
        }
    }

    func connectToG6CGM(txId: String, code: Int?, completion: @escaping (Bool) -> Void) {
        logger.info("Connecting to G6 CGM...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for G6: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let sensorTypeResponse = self.bluetooth.write(
                message: SetSensorTypeRequest(sensorType: .dexcomG6),
                expecting: SetSensorTypeResponse.self
            ) as? SetSensorTypeResponse else {
                self.logger.error("Failed to set Sensortype to G6")
                completion(false)
                return
            }

            guard sensorTypeResponse.isStatusOK else {
                self.logger.error("Failed to set Sensortype to G6 - Status: \(sensorTypeResponse.status)")
                completion(false)
                return
            }

            guard let transmitterResponse = self.bluetooth.write(
                message: SetG6TransmitterIdRequest(txId: txId),
                expecting: SetG6TransmitterIdResponse.self
            ) as? SetG6TransmitterIdResponse else {
                self.logger.error("Failed to set transmitterId for G6")
                completion(false)
                return
            }

            guard transmitterResponse.isStatusOK else {
                self.logger.error("Failed to set transmitterId for G6 - Status: \(transmitterResponse.status)")
                completion(false)
                return
            }

            if let code {
                guard let startSensorResponse = self.bluetooth.write(
                    message: StartDexcomG6SensorSessionRequest(sensorCode: code),
                    expecting: StartDexcomG6SensorSessionResponse.self
                ) as? StartDexcomG6SensorSessionResponse else {
                    self.logger.error("Failed to set start G6")
                    completion(false)
                    return
                }

                guard startSensorResponse.isStatusOK else {
                    self.logger.error("Failed to set start G6 - Status: \(startSensorResponse.status)")
                    completion(false)
                    return
                }
            }

            completion(true)
        }
    }

    func connectToG7CGM(code: Int, completion: @escaping (Bool) -> Void) {
        logger.info("Connecting to G7 CGM...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for G7: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let sensorTypeResponse = self.bluetooth.write(
                message: SetSensorTypeRequest(sensorType: .dexcomG7),
                expecting: SetSensorTypeResponse.self
            ) as? SetSensorTypeResponse else {
                self.logger.error("Failed to set Sensortype to G7")
                completion(false)
                return
            }

            guard sensorTypeResponse.isStatusOK else {
                self.logger.error("Failed to set Sensortype to G7 - Status: \(sensorTypeResponse.status)")
                completion(false)
                return
            }

            guard let startG7 = self.bluetooth.write(
                message: SetDexcomG7PairingCodeRequest(pairingCode: code),
                expecting: SetDexcomG7PairingCodeResponse.self
            ) as? SetDexcomG7PairingCodeResponse else {
                self.logger.error("Failed to start G7")
                completion(false)
                return
            }

            guard startG7.isStatusOK else {
                self.logger.error("Failed to start G7 - Status: \(startG7.status)")
                completion(false)
                return
            }

            completion(true)
        }
    }
}

// MARK: - PumpCommDelegate Conformance

extension TandemPumpManager {
    func getActivePumpEvents(endDate: Date? = nil) -> [NewPumpEvent] {
        guard state.basalDose.type == .tempBasal else {
            return []
        }

        let basalEntry = state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
        return [
            NewPumpEvent.tempBasal(
                dose: basalEntry,
                date: basalEntry.startDate
            )
        ]
    }

    func emitPumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool = true) {
        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.logger.warning("No pump delegate, not notifying...")
                return
            }

            delegate.pumpManager(
                self,
                hasNewPumpEvents: events,
                lastReconciliation: self.state.lastReconciliation,
                replacePendingEvents: replacePendingEvents
            ) { _ in }
        }
    }

    func getScheduledBasalRate() -> Double {
        let schedule = state.basalRateSchedule
        guard !schedule.items.isEmpty else {
            return 0
        }

        let now = Date.now
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        return schedule.items.last(where: { $0.startTime < nowTimeInterval })?.value ?? schedule.items[0].value
    }
}

private extension TandemPumpManager {
    func releaseBolusPermission(bolusId: Int) {
        guard let response = bluetooth.write(
            message: BolusPermissionReleaseRequest(bolusID: bolusId),
            expecting: BolusPermissionReleaseResponse.self
        ) as? BolusPermissionReleaseResponse else {
            logger.error("Error releasing bolus permission for id \(bolusId)")
            return
        }

        if response.status != 0 {
            logger.error("Failed to release bolus permission for id \(bolusId) with status \(response.status)")
        }
    }
}

extension TandemPumpManager: AlertResponder, AlertSoundVendor {
    public func getSoundBaseURL() -> URL? {
        nil
    }

    public func getSounds() -> [LoopKit.Alert.Sound] {
        []
    }

    public func acknowledgeAlert(alertIdentifier _: LoopKit.Alert.AlertIdentifier, completion: @escaping ((any Error)?) -> Void) {
        completion(nil)
    }
}

extension TandemPumpManager {
    private static func strideRange(
        from start: Double,
        through end: Double,
        by step: Double
    ) -> [Double] {
        let multiplier = 1000.0

        let startInt = Int(round(start * multiplier))
        let endInt = Int(round(end * multiplier))
        let stepInt = Int(round(step * multiplier))

        return stride(from: startInt, through: endInt, by: stepInt).map {
            Double($0) / multiplier
        }
    }
}
