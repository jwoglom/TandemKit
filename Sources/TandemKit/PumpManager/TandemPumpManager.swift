import Combine
import CoreBluetooth
import Dispatch
import Foundation
import HealthKit
import LoopKit
import UIKit

// MARK: - Scan Device Observer Protocol

public struct TandemPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]?
}

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
        state.pumpState.valid == true
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
        10 * 60 // 10 minutes in seconds
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

    public var insulinDeliveryActionsEnabled: Bool {
        state.insulinDeliveryActionsEnabled
    }

    public var connectionSharingEnabled: Bool {
        state.connectionSharingEnabled
    }

    public var autoAcknowledgeBasalAlerts: Bool {
        state.autoAcknowledgeBasalAlerts
    }

    private func handleFillTubingStateStream(_ response: FillTubingStateStreamResponse) {
        logger.debug("[notification] Fill tubing button state: \(response.buttonDown)")
        fillTubingStateStream.send(response)
    }

    private func autoAcknowledgeBasalAlertsIfNeeded(alertResponse: AlertStatusResponse) {
        let basalAlertsToAck = alertResponse.alerts.intersection(
            AlertStatusResponse.AlertResponseType.basalAlertsToIgnoreWhenLooping
        )

        guard !basalAlertsToAck.isEmpty else {
            return
        }

        logger.info("[auto-ack] Found \(basalAlertsToAck.count) basal alert(s) to acknowledge: \(basalAlertsToAck)")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for autoAck: \(error.localizedDescription)")
                return
            }

            for alert in basalAlertsToAck {
                guard let response = self.bluetooth.write(
                    message: DismissNotificationRequest(
                        notificationType: .alert,
                        notificationId: UInt32(alert.rawValue)
                    ),
                    expecting: DismissNotificationResponse.self
                ) as? DismissNotificationResponse else {
                    self.logger.error("Failed to send DismissNotificationRequest")
                    return
                }

                if response.status != 0 {
                    self.logger.warning("[auto-ack] Failed to acknowledge \(alert): status=\(response.status)")
                }
            }
        }
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

    // MARK: - Control-IQ / DIY Algorithm Mode

    private var isControlIQModeActive: Bool {
        state.useControlIQ
    }

    public func configureControlIQMode(_ request: ChangeControlIQSettingsRequest, completion: @escaping (Bool) -> Void) {
        logger.info("Configure controlIQ mode: \(request.enabled)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            do {
                // When switching to ControlIQ, cancel any active DIY temp basal first
//                if request.enabled, self.state.basalDose.type == .tempBasal {
//                    self.logger
//                        .info("[configureControlIQMode] Cancelling active DIY temp basal before enabling ControlIQ")
//                    let _: StopTempRateResponse = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: StopTempRateRequest(),
//                        expecting: StopTempRateResponse.self
//                    )
//
//                    let dose = UnfinalizedDose(
//                        basalRate: self.getScheduledBasalRate(),
//                        insulinType: self.state.insulinType,
//                        startDate: Date.now
//                    )
//                    var events = self.getActivePumpEvents(endDate: dose.startDate)
//                    events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))
//
//                    self.state.basalDose = dose
//                    self.state.lastReconciliation = Date.now
//                    self.notifyDelegateStateUpdated()
//                    self.emitPumpEvents(events)
//                }
//
//                let response: ChangeControlIQSettingsResponse = try self.pumpComm.sendMessage(
//                    transport: transport,
//                    message: request,
//                    expecting: ChangeControlIQSettingsResponse.self
//                )
//
//                guard response.isStatusOK else {
//                    self.logger
//                        .error("[configureControlIQMode] Pump rejected ControlIQ change to enabled=\(request.enabled)")
//                    throw PumpCommError.errorResponse(
//                        context: String(
//                            localized: "Pump rejected Control-IQ settings change",
//                            comment: "Message when pump rejects ControlIQ settings change"
//                        ),
//                        request: request,
//                        response: response
//                    )
//                }
            } catch {
                self.logger.error("[configureControlIQMode] Failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            // Pump accepted -- update local preference
            state.useControlIQ = request.enabled
            state.controlIQWeight = request.weightLbs
            state.controlIQTotalDailyInsulin = request.totalDailyInsulinUnits
            self.notifyDelegateStateUpdated()

            self.logger.info("Algorithm mode set to \(request.enabled ? "Control-IQ" : "DIY")")

            // Refresh pump state to confirm ControlIQ status
            Thread.sleep(forTimeInterval: 1.0)
            self.ensureCurrentPumpData { _ in
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
    }

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        bluetooth.ensureConnected { error in
            if let error {
                completion?(self.state.lastReconciliation)
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

    // MARK: - Dose Delivery Methods

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        logger.info("Enacting bolus - units \(units)U")

        if let error = validateBolusRequest(units: units, activationType) {
            logger
                .error("[enactBolus] could not validate bolus request: units=\(units) activationType=\(activationType)")
            completion(error)
            return
        }

        if isControlIQModeActive, activationType.isAutomatic {
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
        guard !isControlIQModeActive else {
            logger.warning("[enactTempBasal] Blocked: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let baselineRate = self.getScheduledBasalRate()
                guard baselineRate > 0 else {
                    self.logger.error("No scheduled basal rate present or is 0, cannot enact temp basal")
                    throw PumpCommError.invalidScheduledBasalRate
                }

                // Query pump's current temp basal state, in case there is an active temp basal we don't have in our own state
//                let currentTempRate: TempRateResponse = try self.pumpComm.sendMessage(
//                    transport: transport,
//                    message: TempRateRequest(),
//                    expecting: TempRateResponse.self
//                )
//
//                if currentTempRate.active {
//                    let response: StopTempRateResponse = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: StopTempRateRequest(),
//                        expecting: StopTempRateResponse.self
//                    )
//
//                    guard response.isStatusOK else {
//                        self.telemetryLogger.error("Failed to cancel temp basal - status: \(response.status)")
//                        throw PumpCommError.errorResponse(
//                            context: String(
//                                localized: "Pump failed to cancel temp basal",
//                                comment: "Message when pump rejects request to stop temp rate"
//                            ),
//                            request: StopTempRateRequest(),
//                            response: response
//                        )
//                    }
//
//                    logger.info("Canceled running temp basal!")
//                }
//
//                let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)
//                let absoluteRate = self
//                    .roundToSupportedBasalRate(unitsPerHour: Double(baselineRate * (Double(percent) / 100)))
//
//                if duration < .ulpOfOne || percent == 100 {
//                    // We only needed to cancel any current temp basal
//                    let dose = UnfinalizedDose(
//                        basalRate: baselineRate,
//                        insulinType: state.insulinType,
//                        startDate: Date.now
//                    )
//                    var events = self.getActivePumpEvents(endDate: dose.startDate)
//                    events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))
//
//                    state.basalDose = dose
//                    state.lastReconciliation = Date.now
//                    self.notifyDelegateStateUpdated()
//                    self.emitPumpEvents(events)
//                    completion(nil)
//                    return
//                }
//
//                if absoluteRate < unitsPerHour {
//                    self.telemetryLogger
//                        .warning(
//                            "Temp basal percentage limit reached: can only set \(absoluteRate)U/hr instead of requested \(unitsPerHour)U/hr"
//                        )
//                }
//
//                let request = SetTempRateRequest(minutes: Int(duration.minutes), percent: percent)
//                let response: SetTempRateResponse = try self.pumpComm.sendMessage(
//                    transport: transport,
//                    message: request,
//                    expecting: SetTempRateResponse.self
//                )
//
//                if !response.isStatusOK {
//                    self.telemetryLogger.error("enactTempBasal: SetTempRateResponse returned error status: \(response.status)")
//                    throw PumpCommError.errorResponse(
//                        context: String(
//                            localized: "Pump failed to cancel temp basal",
//                            comment: "Message when pump rejects request to stop temp rate"
//                        ),
//                        request: request,
//                        response: response
//                    )
//                }
//
//                let dose = UnfinalizedDose(
//                    tempRate: absoluteRate,
//                    duration: duration,
//                    automatic: true,
//                    insulinType: state.insulinType,
//                )
//                var events = self.getActivePumpEvents(endDate: dose.startDate)
//                events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(), date: dose.startDate))
//
//                state.basalDose = dose
//                state.lastReconciliation = dose.startDate
//
//                self.notifyDelegateStateUpdated()
//                self.emitPumpEvents(events)
//
//                logger.info("Temp basal enacted!")
                completion(nil)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                completion(.communication(pumpError))
            }
        }
    }

    private var currentSettings: TandemPumpManagerSettings {
        state.settings
    }

    private var latestInsulinOnBoard: Double? {
        state.latestInsulinOnBoard
    }

    private func validateBolusRequest(units: Double, _: BolusActivationType) -> PumpManagerError? {
        guard units > 0 else {
            return .deviceState(TandemPumpManagerValidationError.invalidBolusAmount(requested: units))
        }

        if let maxBolus = currentSettings.maxBolus, units > maxBolus {
            return .deviceState(TandemPumpManagerValidationError.maximumBolusExceeded(requested: units, maximum: maxBolus))
        }

        if let maxIOB = currentSettings.maxInsulinOnBoard,
           let currentIOB = latestInsulinOnBoard,
           currentIOB + units > maxIOB
        {
            return .deviceState(
                TandemPumpManagerValidationError.insulinOnBoardLimitExceeded(
                    currentIOB: currentIOB,
                    requested: units,
                    maximum: maxIOB
                )
            )
        }

        return nil
    }

    // MARK: - Delivery Control Methods

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

    public func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void
    ) {
        logger.info("Sync basal schedule...")
        guard !scheduleItems.isEmpty else {
            logger.error("Basal schedule is empty")
            completion(.failure(PumpManagerError.configuration(nil)))
            return
        }

        let sortedItems = scheduleItems.sorted { $0.startTime < $1.startTime }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Fetch current profile data using IDPManager
                let idpManager = IDPManager()

                // Fetch all IDP data until complete
//                while !idpManager.isComplete {
//                    let messages = idpManager.nextMessages()
//                    if messages.isEmpty, !idpManager.isComplete {
//                        throw PumpCommError.requestConstructionFailed(
//                            reason: "Invalid IDPManager state in syncBasalRateSchedule"
//                        )
//                    }
//                    for message in messages {
//                        let response = try self.pumpComm.sendMessage(
//                            transport: transport,
//                            message: message
//                        )
//                        idpManager.processMessage(response)
//                    }
//                }
//
//                if idpManager.getProfiles().isEmpty == true {
//                    self.telemetryLogger.info("No profiles in IDPManager, creating initial profile for Trio")
//                    // TODO(jwoglom): read correct profile defaults
//                    let message = idpManager.createNewProfileMessage(
//                        profileName: "TandemKitProfile",
//                        defaultCarbRatio: 10,
//                        defaultBasalRateUnits: scheduleItems.first?.value ?? 0,
//                        defaultTargetBG: 110,
//                        defaultISF: 40,
//                        defaultInsulinDurationMinutes: 240,
//                        profileCarbEntryEnabled: false
//                    )
//                    let newlyCreatedProfile = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: message
//                    )
//
//                    guard let newlyCreatedProfile = newlyCreatedProfile as? CreateIDPResponse else {
//                        throw PumpCommError
//                            .requestConstructionFailed(
//                                reason: "No active profile found and got unexpected response creating initial profile"
//                            )
//                    }
//
//                    guard newlyCreatedProfile.isStatusOK else {
//                        throw PumpCommError
//                            .requestConstructionFailed(reason: "No active profile found and failed to create initial profile")
//                    }
//
//                    self.telemetryLogger
//                        .info("Created initial IDP profile with ID \(String(describing: newlyCreatedProfile.newIdpId))")
//
//                    // Return to step 1: Reset idpManager
//                    idpManager.clear()
//
//                    // Fetch all IDP data until complete
//                    while !idpManager.isComplete {
//                        let messages = idpManager.nextMessages()
//                        for message in messages {
//                            let response = try self.pumpComm.sendMessage(
//                                transport: transport,
//                                message: message
//                            )
//                            idpManager.processMessage(response)
//                        }
//                    }
//                }
//
//                // Step 2: Get the active profile
//                guard let activeProfile = idpManager.getActiveProfile() else {
//                    throw PumpCommError.requestConstructionFailed(reason: "No active profile found")
//                }
//
//                // Step 3: Get current segments to preserve non-basal fields
//                let currentSegments = activeProfile.getSegments()
//
//                // Step 4: Build modify requests for each new basal schedule item
//                var modifyRequests: [SetIDPSegmentRequest] = []
//
//                for (index, scheduleItem) in sortedItems.enumerated() {
//                    let startMinutes = Int((scheduleItem.startTime / 60.0).rounded())
//                    let basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())
//
//                    if index < currentSegments.count {
//                        // Check if existing segment needs modification
//                        let currentSegment = currentSegments[index]
//                        let needsUpdate = currentSegment.profileStartTime != startMinutes ||
//                            currentSegment.profileBasalRate != basalMilliunits
//
//                        if needsUpdate {
//                            let segment = currentSegment
//                            segment.profileStartTime = startMinutes
//                            segment.profileBasalRate = basalMilliunits
//                            let request = activeProfile.modifySegmentMessage(segment: segment)
//                            modifyRequests.append(request)
//                        }
//                    } else {
//                        // Create new segment with default values from first segment
//                        let firstSegment = currentSegments.first!
//                        let request = activeProfile.createSegmentMessage(
//                            profileStartTime: startMinutes,
//                            profileBasalRate: basalMilliunits,
//                            profileCarbRatio: firstSegment.profileCarbRatio,
//                            profileTargetBG: Int(firstSegment.profileTargetBG),
//                            profileISF: firstSegment.profileISF
//                        )
//                        modifyRequests.append(request)
//                    }
//                }
//
//                // Step 5: If we have fewer items than current segments, delete extra segments
//                if sortedItems.count < currentSegments.count {
//                    for i in sortedItems.count ..< currentSegments.count {
//                        if i > 0 { // Can't delete segment 0
//                            let deleteRequest = activeProfile.deleteSegmentMessage(segment: currentSegments[i])
//                            modifyRequests.append(deleteRequest)
//                        }
//                    }
//                }
//
//                // Step 6: Send all modification requests
//                for request in modifyRequests {
//                    let response: SetIDPSegmentResponse = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: request,
//                        expecting: SetIDPSegmentResponse.self
//                    )
//
//                    guard response.status == 0 else {
//                        throw PumpCommError.errorResponse(
//                            context: String(
//                                localized: "Error syncing basal rates: Pump rejected SetIDPSegment",
//                                comment: "Message when pump rejects SetIDPSegment"
//                            ),
//                            request: request,
//                            response: response
//                        )
//                    }
//                }
//
//                let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: TimeZone.current) ?? state.basalRateSchedule
//
//                var managerState = self.state
//                managerState.basalRateSchedule = schedule
//                managerState.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
//                self.state = managerState
//
//                self.notifyDelegateStateUpdated()
                completion(.success(
                    BasalRateSchedule(dailyItems: sortedItems, timeZone: TimeZone.current) ?? state
                        .basalRateSchedule
                ))
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.notifyPumpManagerDelegateOfError(pumpError)
                logger.error("Received error during basal sync: \(pumpError.errorDescription ?? "")")
                completion(.failure(PumpManagerError.communication(pumpError)))
            }
        }
    }

    public func syncDeliveryLimits(
        limits _: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    ) {
        logger.info("syncDeliveryLimits...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
                var appliedLimits = DeliveryLimits(maximumBasalRate: nil, maximumBolus: nil)

//                if let maxBasal = deliveryLimits.maximumBasalRate?.doubleValue(for: hkUnit) {
//                    let milliunits = Int((maxBasal * 1000.0).rounded())
//                    let request = SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits)
//                    let response: SetMaxBasalLimitResponse = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: request,
//                        expecting: SetMaxBasalLimitResponse.self
//                    )
//
//                    guard response.status == 0 else {
//                        throw PumpCommError.errorResponse(
//                            context: String(
//                                localized: "Error setting max basal limit",
//                                comment: "Message when pump rejects SetMaxBasalLimit"
//                            ),
//                            request: request,
//                            response: response
//                        )
//                    }
//
//                    appliedLimits.maximumBasalRate = HKQuantity(unit: hkUnit, doubleValue: maxBasal)
//                }
//
//                if let maxBolus = deliveryLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit()) {
//                    let milliunits = Int((maxBolus * 1000.0).rounded())
//                    let request = SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits)
//                    let response: SetMaxBolusLimitResponse = try self.pumpComm.sendMessage(
//                        transport: transport,
//                        message: request,
//                        expecting: SetMaxBolusLimitResponse.self
//                    )
//
//                    guard response.status == 0 else {
//                        throw PumpCommError.errorResponse(
//                            context: String(
//                                localized: "Error setting max bolus limit",
//                                comment: "Message when pump rejects SetMaxBolusLimit"
//                            ),
//                            request: request,
//                            response: response
//                        )
//                    }
//
//                    appliedLimits.maximumBolus = HKQuantity(unit: HKUnit.internationalUnit(), doubleValue: maxBolus)
//                }
//
//                let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
//                var managerState = self.state
//                managerState.settings.maxTempBasalRate = appliedLimits.maximumBasalRate?.doubleValue(for: hkUnit)
//                managerState.settings.maxBolus = appliedLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit())
//                self.state = managerState
//
//                self.notifyDelegateStateUpdated()

                completion(.success(appliedLimits))
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.delegateQueue.async {
                    completion(.failure(PumpManagerError.communication(pumpError)))
                }
            }
        }
    }

    public func syncPumpTime(completion: @escaping (Result<Void, PumpManagerError>) -> Void) {
        logger.info("Syncing pump time")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
//                let epoch = Dates.fromInstantToJan12008EpochSeconds(Date.now)
//                let request = ChangeTimeDateRequest(tandemEpochTime: UInt32(epoch))
//                let response: ChangeTimeDateResponse = try pumpComm.sendMessage(
//                    transport: transport,
//                    message: request,
//                    expecting: ChangeTimeDateResponse.self
//                )
//
//                if !response.isStatusOK {
//                    logger.error("Pump time sync failed, status NOK!")
//
//                    let error = PumpCommError.errorResponse(
//                        context: String(
//                            localized: "Error syncing time with pump",
//                            comment: "Message when pump rejects ChangeTimeDateRequest"
//                        ),
//                        request: request,
//                        response: response
//                    )
//                    completion(.failure(PumpManagerError.communication(error)))
//                } else {
//                    completion(.success(()))
//                }
                completion(.success(()))
            } catch {
                logger.error("Failed to sync pump time: \(error.localizedDescription)")

                let pumpError = PumpCommError.other
                completion(.failure(PumpManagerError.communication(pumpError)))
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

    func setPumpSound(request _: SetPumpSoundsRequest) {
        do {
//            _ = try pumpComm.sendMessage(
//                transport: transport,
//                message: request,
//                expecting: SetPumpSoundsResponse.self
//            )
//
//            // Allow the patch to set values
//            Thread.sleep(forTimeInterval: .seconds(1))
//            fetchGlobalPumpSettings(transport: transport)
        } catch {
            logger.error("Failed to pump sounds: \(error.localizedDescription)")
        }
    }

    // MARK: - Play Sound

    func playSound() {
        do {
//            _ = try pumpComm.sendMessage(
//                transport: transport,
//                message: PlaySoundRequest(),
//                expecting: PlaySoundResponse.self
//            )
        } catch {
            logger.error("Failed to play sound: \(error.localizedDescription)")
        }
    }

    // MARK: - Alert Snooze

    func setAlertSnooze(enabled _: Bool, durationMins _: Int) {
        do {
//            let response: SetPumpAlertSnoozeResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: SetPumpAlertSnoozeRequest(snoozeEnabled: enabled, snoozeDurationMins: durationMins),
//                expecting: SetPumpAlertSnoozeResponse.self
//            )
//
//            guard response.isStatusOK else {
//                logger.error("Failed to set alert snooze: status \(response.status)")
//                return
//            }
//
//            var managerState = state
//            managerState.alertSnoozeEnabled = enabled
//            managerState.alertSnoozeDuration = TimeInterval(minutes: Double(durationMins))
//            state = managerState
//            notifyDelegateStateUpdated()
//
//            logger.info("Alert snooze set: enabled=\(enabled), duration=\(durationMins)m")
        } catch {
            logger.error("Failed to set alert snooze: \(error.localizedDescription)")
        }
    }

    // MARK: - Quick Bolus Settings

    func setQuickBolusSettings(enabled _: Bool, mode _: QuickBolusMode, increment _: QuickBolusIncrement) {
        do {
//            let response: SetQuickBolusSettingsResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: SetQuickBolusSettingsRequest(enabled: enabled, mode: mode, increment: increment),
//                expecting: SetQuickBolusSettingsResponse.self
//            )
//
//            guard response.isStatusOK else {
//                logger.error("Failed to set quick bolus settings: status \(response.status)")
//                return
//            }
//
//            Thread.sleep(forTimeInterval: .seconds(1))
//            fetchGlobalPumpSettings(transport: transport)
        } catch {
            logger.error("Failed to set quick bolus settings: \(error.localizedDescription)")
        }
    }
}

extension TandemPumpManager {
//    public func tandemPump(
//        _: TandemPump,
//        didCompleteConfiguration peripheralManager: PeripheralManager
//    ) {
//        // Only create a new transport if we don't have one yet, or if the peripheral manager changed
//        let needsNewTransport = transportLock.value == nil || activePeripheralManager !== peripheralManager
//
//        if needsNewTransport {
//            telemetryLogger.info("Creating new transport for peripheral manager")
//            let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
//            updateTransport(transport)
//        } else {
//            telemetryLogger.info("Reusing existing transport - peripheral manager unchanged")
//        }
//
//        activePeripheralManager = peripheralManager
//        peripheralManager.activityHandler = { [weak self] in
//            self?.updateLastHeartbeatIfNeeded()
//        }
//        notificationRouter.start(with: peripheralManager, session: pumpComm.getSession())
//
//        updateBLEHeartbeatPreference()
//        scheduleInitialConnectionTimeoutCheck()
//    }
//
//    /// Schedule a 5-second post-initialization timeout check.
//    ///
//    /// After BLE initialization completes and startup messages are dispatched,
//    /// this verifies that at least one response has been received. If no responses
//    /// arrived within the window and no auth bootstrap is running, the pump is
//    /// soft-disconnected so the connection can be retried automatically.
//    /// This mirrors PumpX2's `checkIfInitialPumpConnectionEstablished()`.
//    private func scheduleInitialConnectionTimeoutCheck() {
//        // Reset counters for this connection attempt
//        processedResponseMessages.value = 0
//        initialConnectionTimeoutAttempts.value = 0
//
//        scheduleNextInitialConnectionTimeout()
//    }
//
//    private func scheduleNextInitialConnectionTimeout() {
//        // Cancel any previously scheduled check
//        initialConnectionTimeoutWork?.cancel()
//
//        let work = DispatchWorkItem { [weak self] in
//            guard let self = self else { return }
//
//            let repliesReceived = self.processedResponseMessages.value
//            let bootstrapRunning = self.sessionBootstrapInProgress.value
//            let pairing = self.pairingInProgress.value
//            let attempt = self.initialConnectionTimeoutAttempts.value
//
//            if repliesReceived > 0 {
//                self.telemetryLogger.info(
//                    "InitialConnectionTimeout: received \(repliesReceived) response(s) – connection healthy"
//                )
//            } else if pairing {
//                // JPAKE handshake is in progress (first SwiftECC round can take >10s).
//                // Do not disconnect — pairing manages its own lifecycle.
//                self.telemetryLogger.info(
//                    "InitialConnectionTimeout: pairing in progress – skipping disconnect"
//                )
//            } else if bootstrapRunning, attempt < self.initialConnectionTimeoutMaxAttempts {
//                self.initialConnectionTimeoutAttempts.value += 1
//                self.telemetryLogger.info(
//                    "InitialConnectionTimeout: auth bootstrap still in progress (attempt \(attempt + 1)/\(self.initialConnectionTimeoutMaxAttempts)) – extending timeout"
//                )
//                self.scheduleNextInitialConnectionTimeout()
//                return
//            } else {
//                self.telemetryLogger.error(
//                    "InitialConnectionTimeout: no responses received (bootstrap=\(bootstrapRunning), attempt=\(attempt)) – soft disconnecting for retry"
//                )
//                self.tandemPump.softDisconnect()
//            }
//            self.initialConnectionTimeoutWork = nil
//        }
//
//        initialConnectionTimeoutWork = work
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
//    }

//    public func tandemPump(
//        _: TandemPump,
//        didDisconnectWithError error: Error?
//    ) {
//        telemetryLogger.error("Pump disconnected with error: \(String(describing: error))")
//
//        // Cancel any pending initial connection timeout check
//        initialConnectionTimeoutWork?.cancel()
//        initialConnectionTimeoutWork = nil
//        processedResponseMessages.value = 0
//        initialConnectionTimeoutAttempts.value = 0
//
//        if let manager = activePeripheralManager {
//            notificationRouter.stop(with: manager)
//            activePeripheralManager = nil
//        }
//
//        updateTransport(nil)
//
//        if isOnboarded {
//            telemetryLogger.debug("Pump disconnected – restarting scan to reconnect")
//            tandemPump.startScanning()
//        }
//    }
}

// MARK: - PumpCommDelegate Conformance

extension TandemPumpManager {
    internal func getActivePumpEvents(endDate: Date? = nil) -> [NewPumpEvent] {
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

    internal func emitPumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool = true) {
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

    public func pumpComm(didReceiveQualifyingEvents events: Set<QualifyingEvent>) {
        logger.info("[notification] Received qualifying events: \(events)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let handlers = QualifyingEvent.groupSuggestedHandlers(events)
            logger.debug("[notification] Fetching \(handlers.count) status messages for qualifying events")

            for message in handlers {
                do {
                    // Let the notification handler deal with the results
//                    let _ = try self.pumpComm.sendMessage(transport: transport, message: message)
                } catch {
                    self.logger.error("[notification] Failed to fetch handler for qualifying event: \(error)")
                }
            }
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
