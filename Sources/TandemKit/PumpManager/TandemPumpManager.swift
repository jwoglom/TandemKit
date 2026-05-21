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
    public let rssi: NSNumber
}

public protocol StateObserver: AnyObject {
    func deviceScanDidUpdate(_ device: TandemPumpScan)
}

struct ActiveBolus {
    let id: Int
    let dose: UnfinalizedDose
}

enum ResponseSource {
    case telemetry
    case notification

    var label: String {
        switch self {
        case .telemetry:
            return "telemetry"
        case .notification:
            return "notification"
        }
    }
}

public class TandemPumpManager: PumpManager, Pluggable {
    public static var pluginIdentifier: String = "TandemPumpManager"

    public var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    public typealias RawStateValue = [String: Any]

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
    internal let transportLock = Locked<PumpMessageTransport?>(nil)
    public let tandemPump: TandemPump
    private let telemetryLogger = TandemLogger(category: "TandemPumpManager.Telemetry")
    private let notificationRouter = PumpNotificationRouter()
    private let notificationLogger = TandemLogger(category: "TandemPumpManager.Notifications")
    private let lockedNotificationBundle = Locked<NotificationBundle>(NotificationBundle())
    internal let telemetryScheduler = PumpTelemetryScheduler(label: "com.loopkit.TandemKit.TelemetryScheduler")

    // Status tracking
    private let statusObservers = Locked<[UUID: (observer: PumpManagerStatusObserver, queue: DispatchQueue)]>([:])
    private let scanDeviceObservers = WeakSynchronizedSet<StateObserver>()
    private let inScanningMode = Locked<Bool>(false)

    // Stream message publishers
    public let fillTubingStateStream = PassthroughSubject<FillTubingStateStreamResponse, Never>()
    private let sessionInitializationQueue = DispatchQueue(label: "com.jwoglom.TandemKit.sessionInit")
    internal let needsSessionInitialization = Locked<Bool>(false)
    private let sessionBootstrapInProgress = Locked<Bool>(false)
    private let sessionBootstrapRetryAttempt = Locked<Int>(0)
    internal let activeBolus = Locked<ActiveBolus?>(nil)
    internal var bolusProgressReport: TandemDoseProgressReporter?
    private var telemetryConfigured = false
    private weak var activePeripheralManager: PeripheralManager?
    private var targetPeripheralIdentifier: UUID?
    private let silentToneManager = TandemSilentToneManager()

    // BLE heartbeat propagation (LoopKit PumpManager protocol)
    private var provideHeartbeat: Bool = false
    private var lastHeartbeat: Date = .distantPast

    // Post-initialization connection timeout (mirrors PumpX2's checkIfInitialPumpConnectionEstablished)
    private let processedResponseMessages = Locked<Int>(0)
    private var initialConnectionTimeoutWork: DispatchWorkItem?
    private let initialConnectionTimeoutAttempts = Locked<Int>(0)
    private let initialConnectionTimeoutMaxAttempts = 3

    // Pairing-in-progress flag: prevents the connection timeout from
    // soft-disconnecting the pump while the JPAKE handshake is running.
    private let pairingInProgress = Locked<Bool>(false)

    @objc func appMovedToBackground() {
        if state.useSilentTones {
            telemetryLogger.info("Starting silent tones")
            silentToneManager.startBackgroundTask()
        }
    }

    @objc func appMovedToForeground() {
        silentToneManager.stopBackgroundTask()
    }

    func updatePairingArtifacts(with pumpState: PumpState?) {
        PumpStateSupplier.storePairingArtifacts(
            derivedSecret: pumpState?.derivedSecret,
            serverNonce: pumpState?.serverNonce
        )

        // Set the timeSinceReset closure to provide the value from pump state
        PumpStateSupplier.pumpTimeSinceReset = { [weak self] in
            self?.state.pumpState?.timeSinceReset ?? 0
        }
    }

    private func configureStateSuppliers() {
        PumpStateSupplier.currentBolusId = { [weak self] in
            self?.activeBolus.value?.id
        }
    }

    private func clearStalePairingArtifactsIfNeeded() {
        guard var pumpState = state.pumpState,
              pumpState.derivedSecret != nil || pumpState.serverNonce != nil || pumpState.timeSinceReset != nil
        else {
            // Still clear the global supplier so transports stop signing with old keys.
            PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)
            return
        }

        telemetryLogger.debug("Clearing stored authentication artifacts before pairing")
        pumpState.derivedSecret = nil
        pumpState.serverNonce = nil
        pumpState.timeSinceReset = nil
        state.pumpState = pumpState
        pumpComm.syncPumpState(state.pumpState)
        updatePairingArtifacts(with: pumpState)
    }

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    var pumpComm: PumpComm {
        get {
            tandemPump.pumpComm
        }
        set {
            tandemPump.pumpComm = newValue
        }
    }

    public func updateTransport(_ transport: PumpMessageTransport?) {
        transportLock.value = transport

        if let activeTransport = transport {
            telemetryLogger.debug("Transport available – checking authentication before telemetry")

            // Only trigger telemetry if we're already authenticated
            if let pumpState = state.pumpState,
               pumpState.derivedSecret != nil,
               pumpState.serverNonce != nil
            {
                bootstrapAuthenticatedSessionIfNeeded(on: activeTransport)
            } else {
                telemetryLogger.debug("Not authenticated yet – skipping telemetry until pairing completes")
            }
        } else {
            telemetryLogger.debug("Transport cleared – telemetry will pause until reconnect")
            needsSessionInitialization.value = state.pumpState?.valid == true
        }
    }

    private func bootstrapAuthenticatedSessionIfNeeded(on transport: PumpMessageTransport) {
        if needsSessionInitialization.value == false {
            telemetryLogger.debug("Authenticated session already initialized – triggering telemetry refresh")
            ensureCurrentPumpData { _ in }
            telemetryScheduler.trigger(kind: .history)
            return
        }

        if sessionBootstrapInProgress.value {
            telemetryLogger.debug("Session bootstrap already in progress; skipping duplicate trigger")
            return
        }

        sessionBootstrapInProgress.value = true

        sessionInitializationQueue.async { [weak self] in
            guard let self = self else { return }
            self.telemetryLogger.debug("Running authenticated session bootstrap to refresh credentials and TimeSinceReset")

            do {
                try self.reauthenticateIfNeeded(on: transport)
                let response: TimeSinceResetResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: TimeSinceResetRequest(),
                    expecting: TimeSinceResetResponse.self
                )

                self.handleTimeSinceResetResponse(response, source: .telemetry)
                self.needsSessionInitialization.value = false
                self.sessionBootstrapRetryAttempt.value = 0

                // Auth + TimeSinceReset succeeded: pump is alive.
                // Cancel initial connection timeout and mark responses received.
                self.processedResponseMessages.value += 1
                self.initialConnectionTimeoutWork?.cancel()
                self.initialConnectionTimeoutWork = nil

                self.telemetryLogger.debug("Session bootstrap complete – triggering telemetry refresh")
                self.ensureCurrentPumpData { _ in }
                self.telemetryScheduler.trigger(kind: .history)
                self.sessionBootstrapInProgress.value = false
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.telemetryLogger.error("Session bootstrap failed: \(pumpError)")
                self.needsSessionInitialization.value = true
                self.sessionBootstrapInProgress.value = false
                self.scheduleBootstrapRetry(afterFailureWith: pumpError, transport: transport)
            }
        }
    }

    private func reauthenticateIfNeeded(on transport: PumpMessageTransport) throws {
        guard let pumpState = state.pumpState,
              let derivedSecret = pumpState.derivedSecret,
              let peripheralUuid = pumpState.peripheralUuid
        else {
            telemetryLogger
                .error("Stored pump state missing authentication artifacts; cannot reauthenticate before telemetry")
            throw PumpCommError.missingAuthenticationKey
        }

        telemetryLogger.debug("Authenticating reconnect session using stored derived secret")
        try pumpComm.confirmAuthentication(
            transport: transport,
            peripheralUuid: peripheralUuid,
            derivedSecret: derivedSecret
        )
    }

    private func scheduleBootstrapRetry(afterFailureWith _: PumpCommError, transport: PumpMessageTransport) {
        var nextAttempt = sessionBootstrapRetryAttempt.value + 1
        if nextAttempt > 10 { nextAttempt = 10 }
        sessionBootstrapRetryAttempt.value = nextAttempt

        let delay = min(pow(2.0, Double(nextAttempt - 1)), 60.0)
        telemetryLogger.debug("Scheduling session bootstrap retry in \(delay)s (attempt \(nextAttempt))")

        sessionInitializationQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.bootstrapAuthenticatedSessionIfNeeded(on: transport)
        }
    }

    func logger(for source: ResponseSource) -> TandemLogger {
        switch source {
        case .telemetry:
            return telemetryLogger
        case .notification:
            return notificationLogger
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
        tandemPump = TandemPump(pumpState: state.pumpState)
        needsSessionInitialization.value = state.pumpState?.valid == true

        tandemPump.delegate = self
        pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        tandemPump.configureDeliveryActions(enabled: state.insulinDeliveryActionsEnabled)
        tandemPump.configureConnectionSharing(enabled: state.connectionSharingEnabled)
        configureStateSuppliers()

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
        state.pumpState != nil
    }

    private var hasPairedPumpState: Bool {
        state.pumpState?.valid == true
    }

    public var connectedAndPaired: Bool {
        guard let _ = transportLock.value else {
            return false
        }
        return hasPairedPumpState
    }

    public var pairedTransport: PumpMessageTransport? {
        guard let transport = transportLock.value,
              state.pumpState?.valid == true,
              needsSessionInitialization.value == false
        else {
            return nil
        }

        return transport
    }

    private func telemetryTransportIfReady(for kind: PumpTelemetryKind) -> PumpMessageTransport? {
        guard connectedAndPaired else {
            telemetryLogger.debug("Skipping \(kind.logDescription) telemetry – pump not connected/paired")
            return nil
        }

        guard activePeripheralManager != nil else {
            telemetryLogger.debug("Skipping \(kind.logDescription) telemetry – no active peripheral manager")
            return nil
        }

        guard let transport = pairedTransport else {
            telemetryLogger.debug("Skipping \(kind.logDescription) telemetry – paired transport unavailable")
            return nil
        }

        return transport
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

    /// The shared notification bundle that aggregates all notification status responses.
    /// UI components should use this bundle to ensure the badge count and list stay in sync.
    public var notificationBundle: NotificationBundle {
        lockedNotificationBundle.value
    }

    /// Updates the shared notification bundle and syncs the notification count to manager state.
    /// Call this after fetching fresh notification data to keep the badge count accurate.
    public func updateNotificationBundle(_ bundle: NotificationBundle) {
        lockedNotificationBundle.value = bundle

        state.notificationCount = bundle.getNotificationCount()
        state.lastNotificationUpdate = Date.now
        notifyDelegateStateUpdated()
    }

    private func handleFillTubingStateStream(_ response: FillTubingStateStreamResponse) {
        notificationLogger.debug("[notification] Fill tubing button state: \(response.buttonDown)")
        fillTubingStateStream.send(response)
    }

    private func autoAcknowledgeBasalAlertsIfNeeded(alertResponse: AlertStatusResponse, transport: PumpMessageTransport) {
        let basalAlertsToAck = alertResponse.alerts.intersection(
            AlertStatusResponse.AlertResponseType.basalAlertsToIgnoreWhenLooping
        )

        guard !basalAlertsToAck.isEmpty else {
            return
        }

        telemetryLogger.info("[auto-ack] Found \(basalAlertsToAck.count) basal alert(s) to acknowledge: \(basalAlertsToAck)")

        for alert in basalAlertsToAck {
            do {
                let request = DismissNotificationRequest(
                    notificationType: .alert,
                    notificationId: UInt32(alert.rawValue)
                )

                let response: DismissNotificationResponse = try pumpComm.sendMessage(
                    transport: transport,
                    message: request,
                    expecting: DismissNotificationResponse.self
                )

                if response.status == 0 {
                    telemetryLogger.info("[auto-ack] Successfully acknowledged \(alert)")
                } else {
                    telemetryLogger.warning("[auto-ack] Failed to acknowledge \(alert): status=\(response.status)")
                }
            } catch {
                telemetryLogger.error("[auto-ack] Error acknowledging \(alert): \(error)")
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

        for (_, statusObserver) in statusObservers.value {
            statusObserver.queue.async {
                statusObserver.observer.pumpManager(self, didUpdate: status, oldStatus: status)
            }
        }

        oldState = TandemPumpManagerState(rawValue: state.rawValue)
    }

    private func resolvedStartSequence(after startDate: Date?) -> UInt32? {
        if let lastSequence = state.lastHistorySequenceNum {
            return lastSequence &+ 1
        }

        let effectiveStartDate = startDate ?? pumpManagerDelegate?.startDateToFilterNewPumpEvents(for: self)

        // Without a known sequence number, fall back to the earliest available sequence number reported
        // by `HistoryLogStatusResponse`. Returning UInt32.min ensures the history fetch session maps the
        // start to `firstSequenceNum` when logs exist.
        if effectiveStartDate != nil {
            return UInt32.min
        }

        return nil
    }

    // MARK: - Status Observers

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        let uuid = UUID()
        statusObservers.value[uuid] = (observer, queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.value = statusObservers.value.filter { _, value in
            value.observer !== observer
        }
    }

    private func notifyStatusObservers(oldStatus: PumpManagerStatus, newStatus: PumpManagerStatus) {
        guard oldStatus != newStatus else { return }

        for (_, observerInfo) in statusObservers.value {
            observerInfo.queue.async {
                observerInfo.observer.pumpManager(self, didUpdate: newStatus, oldStatus: oldStatus)
            }
        }

        // Also notify the main delegate
        if let delegate = pumpManagerDelegate {
            pumpDelegate.queue.async {
                delegate.pumpManager(self, didUpdate: newStatus, oldStatus: oldStatus)
            }
        }
    }

    // MARK: - Scan Device Observers

    public func addScanDeviceObserver(_ observer: StateObserver, queue: DispatchQueue) {
        scanDeviceObservers.insert(observer, queue: queue)
    }

    public func removeScanDeviceObserver(_ observer: StateObserver) {
        scanDeviceObservers.removeElement(observer)
    }

    func notifyScanDeviceDidChange(_ device: TandemPumpScan) {
        scanDeviceObservers.forEach { observer in
            observer.deviceScanDidUpdate(device)
        }
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

    public func connect() {
        tandemPump.delegate = self
        pumpComm.delegate = self

        if transportLock.value != nil {
            telemetryLogger.debug("connect() called while transport already available – refreshing telemetry")
            return
        }

        guard isOnboarded else {
            telemetryLogger.error("connect() requested before pump is paired")
            notifyPumpManagerDelegateOfError(.missingAuthenticationKey)
            return
        }

        tandemPump.startScanning()
    }

    public func disconnect() {
        // Send graceful disconnect to pump before tearing down BLE
        if let transport = pairedTransport {
            do {
                _ = try pumpComm.sendMessage(
                    transport: transport,
                    message: DisconnectPumpRequest(),
                    expecting: DisconnectPumpResponse.self
                )
            } catch {
                telemetryLogger.debug("Graceful disconnect request failed (non-fatal): \(error.localizedDescription)")
            }
        }

        if let manager = activePeripheralManager {
            notificationRouter.stop(with: manager)
            activePeripheralManager = nil
        }
        updateTransport(nil)
        tandemPump.disconnect()
    }

    public func configureDeliveryActions(_ enabled: Bool) {
        tandemPump.configureDeliveryActions(enabled: enabled)

        state.insulinDeliveryActionsEnabled = enabled
        notifyDelegateStateUpdated()
    }

    public func configureConnectionSharing(_ enabled: Bool) {
        tandemPump.configureConnectionSharing(enabled: enabled)

        state.connectionSharingEnabled = enabled
        notifyDelegateStateUpdated()
    }

    public func configureAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        state.autoAcknowledgeBasalAlerts = enabled
        notifyDelegateStateUpdated()

        telemetryLogger.info("Auto-acknowledge basal alerts \(enabled ? "enabled" : "disabled")")
    }

    public func configureSilentMode(_ enabled: Bool) {
        state.useSilentTones = enabled
        notifyDelegateStateUpdated()

        telemetryLogger.info("Heartbeat mode silent tones \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Control-IQ / DIY Algorithm Mode

    private var isControlIQModeActive: Bool {
        state.useControlIQ
    }

    public func configureControlIQMode(_ request: ChangeControlIQSettingsRequest, completion: @escaping (Bool) -> Void) {
        guard let transport = pairedTransport else {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            do {
                try self.pumpComm.performOnCommandQueue {
                    // When switching to ControlIQ, cancel any active DIY temp basal first
                    if request.enabled, self.state.basalDose.type == .tempBasal {
                        self.telemetryLogger
                            .info("[configureControlIQMode] Cancelling active DIY temp basal before enabling ControlIQ")
                        let _: StopTempRateResponse = try self.pumpComm.sendMessage(
                            transport: transport,
                            message: StopTempRateRequest(),
                            expecting: StopTempRateResponse.self
                        )

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

                    let response: ChangeControlIQSettingsResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: request,
                        expecting: ChangeControlIQSettingsResponse.self
                    )

                    guard response.isStatusOK else {
                        self.telemetryLogger
                            .error("[configureControlIQMode] Pump rejected ControlIQ change to enabled=\(request.enabled)")
                        throw PumpCommError.errorResponse(
                            context: String(
                                localized: "Pump rejected Control-IQ settings change",
                                comment: "Message when pump rejects ControlIQ settings change"
                            ),
                            request: request,
                            response: response
                        )
                    }
                }
            } catch {
                self.telemetryLogger.error("[configureControlIQMode] Failed: \(error.localizedDescription)")
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

            self.telemetryLogger.info("Algorithm mode set to \(request.enabled ? "Control-IQ" : "DIY")")

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
        do {
            try pumpComm.performOnCommandQueue {
                guard let transport = pairedTransport else {
                    telemetryLogger.error("Skipping current Pump data -> Transporter not ready")
                    completion?(nil)
                    return
                }

                self.fetchDeliveryLimits(transport: transport)
                self.fetchReservoirStatus(transport: transport)
                self.fetchBatteryStatus(transport: transport)
                self.fetchBolusStatus(transport: transport)
                self.fetchHomeScreenStatus(transport: transport)
                self.fetchControlIQStatus(transport: transport)
                self.fetchNotificationCount(transport: transport)
                self.fetchTimeSinceReset(transport: transport)
                self.fetchGlobalPumpSettings(transport: transport)

                state.lastReconciliation = Date.now
                self.notifyDelegateStateUpdated()

                completion?(state.lastReconciliation)
            }
        } catch {
            telemetryLogger.error("ensureCurrentPumpData failed: \(error)")
        }
    }

    public func sendMessage(message: Message) -> Message? {
        guard let transport = pairedTransport else {
            return nil
        }
        return try? pumpComm.sendMessage(transport: transport, message: message)
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

    public func setTargetPeripheral(_ peripheralIdentifier: UUID?) {
        targetPeripheralIdentifier = peripheralIdentifier
    }

    public func setScanningMode(_ enabled: Bool) {
        inScanningMode.value = enabled
    }

    private func handleAlertResponse(_ alertResponse: AlertStatusResponse) {
        guard let transport = telemetryTransportIfReady(for: .alerts) else {
            return
        }

        // Auto-acknowledge basal alerts if enabled
        if state.autoAcknowledgeBasalAlerts {
            autoAcknowledgeBasalAlertsIfNeeded(alertResponse: alertResponse, transport: transport)
        }
    }

    public func pairPump(
        with pairingCode: String,
        peripheral: CBPeripheral,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Ensure we don't reuse stale authentication material from a previous pairing.
        // Otherwise telemetry triggers when the transport comes online and the pump
        // immediately disconnects because requests are signed with an invalid key.
        clearStalePairingArtifactsIfNeeded()

        // Prevent the session bootstrap from racing with pairing by clearing the
        // initialization flag *before* BLE connects (didCompleteConfiguration checks it).
        needsSessionInitialization.value = false

        Task {
            do {
                let peripheralUuid = peripheral.identifier.uuidString
                let sanitizedCode = try PumpStateSupplier.sanitizeAndStorePairingCode(pairingCode)
                tandemPump.startScanning()

                var tries = 0
                while peripheral.state != .connected {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    telemetryLogger
                        .debug("Waiting for peripheral to be in connected state, in \(peripheral.state): \(peripheral)")
                    tries += 1

                    if tries >= 50 {
                        pairingInProgress.value = false
                        completion(.failure(NSError(
                            domain: "Gave up waiting for peripheral to connect",
                            code: -1
                        )))
                        return
                    }
                }

                // Also wait for transport to be initialized (didCompleteConfiguration must have been called)
                tries = 0
                while transportLock.value == nil {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    telemetryLogger.debug("Waiting for transport to be initialized...")
                    tries += 1

                    if tries >= 50 {
                        pairingInProgress.value = false
                        completion(.failure(NSError(
                            domain: "Gave up waiting for transport initialization",
                            code: -2
                        )))
                        return
                    }
                }

                guard let transport = transportLock.value else {
                    telemetryLogger.error("pumpNotConnected during pairing")
                    pairingInProgress.value = false
                    completion(.failure(PumpCommError.pumpNotConnected))
                    return
                }

                // Cancel the initial connection timeout — the JPAKE handshake
                // (especially the first SwiftECC round) can take >10 seconds and
                // the timeout would soft-disconnect the pump mid-handshake.
                initialConnectionTimeoutWork?.cancel()
                initialConnectionTimeoutWork = nil
                pairingInProgress.value = true
                telemetryLogger.info("Pairing started – connection timeout cancelled")

                // pair() now handles: JPAKE + 250ms wait + TimeSinceResetRequest
                try pumpComm.pair(transport: transport, peripheralUuid: peripheralUuid, pairingCode: sanitizedCode)

                pairingInProgress.value = false
                processedResponseMessages.value += 1
                telemetryLogger.info("Succesfully paired!")
                completion(.success(()))
            } catch {
                pairingInProgress.value = false
                telemetryLogger.error("Failed to pair: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Dose Delivery Methods

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        telemetryLogger.info("Enacting bolus - units \(units)U")

        guard let transport = pairedTransport else {
            telemetryLogger.error("[enactBolus] could not enact bolus because no paired transport")
            completion(.communication(PumpCommError.pumpNotConnected))
            return
        }

        if let error = validateBolusRequest(units: units, activationType) {
            telemetryLogger
                .error("[enactBolus] could not validate bolus request: units=\(units) activationType=\(activationType)")
            completion(error)
            return
        }

        if isControlIQModeActive, activationType.isAutomatic {
            telemetryLogger.warning("[enactBolus] Blocked automatic bolus: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var permissionBolusId: Int?
            var shouldReleasePermissionOnFailure = false

            do {
                let permissionResponse: BolusPermissionResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: BolusPermissionRequest(),
                    expecting: BolusPermissionResponse.self
                )

                guard permissionResponse.isPermissionGranted else {
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump rejected bolus permission request",
                            comment: "Message when pump disallows bolus from occurring"
                        ),
                        request: BolusPermissionRequest(),
                        response: permissionResponse
                    )
                }

                permissionBolusId = permissionResponse.bolusId
                shouldReleasePermissionOnFailure = true

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

                self.telemetryLogger.info("[enactBolus] sending InitiateBolusRequest=\(bolusRequest)")

                let initiateResponse: InitiateBolusResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: bolusRequest,
                    expecting: InitiateBolusResponse.self
                )

                guard initiateResponse.wasBolusInitiated else {
                    self.telemetryLogger.info("[enactBolus] bolus not initiated")
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump rejected bolus initiate request",
                            comment: "Message when pump disallows bolus from occurring"
                        ),
                        request: bolusRequest,
                        response: initiateResponse
                    )
                }

                self.telemetryLogger.info("[enactBolus] bolus started")

                shouldReleasePermissionOnFailure = false

                let dose = UnfinalizedDose(
                    units: units,
                    // 5s needed before bolus enacting is started
                    duration: self.estimatedDuration(toBolus: units) + .seconds(5),
                    activationType: activationType,
                    insulinType: self.state.insulinType
                )

                let doseEntry = dose.toDoseEntry()
                bolusProgressReport = TandemDoseProgressReporter(
                    pumpManager: self,
                    dose: doseEntry,
                    activationType: activationType
                )
                telemetryScheduler.schedule(kind: .bolus, interval: .seconds(1), leeway: .seconds(0.5)) {
                    guard let transport = self.pairedTransport else { return }
                    self.fetchBolusStatus(transport: transport)
                }

                self.activeBolus.value = ActiveBolus(
                    id: initiateResponse.bolusId,
                    dose: dose
                )

                state.bolusState = .initiating
                state.lastReconciliation = Date.now
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents([NewPumpEvent.bolus(dose: doseEntry, units: units)], replacePendingEvents: false)

                completion(nil)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                if shouldReleasePermissionOnFailure, let bolusId = permissionBolusId {
                    self.releaseBolusPermission(transport: transport, bolusId: bolusId)
                }

                completion(.communication(pumpError))
            }
        }
    }

    public func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void) {
        telemetryLogger.info("Cancelling bolus...")

        guard let transport = pairedTransport else {
            telemetryLogger.error("Pump not connected...")
            completion(.failure(.communication(PumpCommError.pumpNotConnected)))
            return
        }

        guard let active = activeBolus.value else {
            telemetryLogger.error("No active bolus...")
            completion(.failure(.communication(PumpCommError.noActiveBolus)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let request = CancelBolusRequest(bolusId: active.id)
                let response: CancelBolusResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: request,
                    expecting: CancelBolusResponse.self
                )

                guard response.wasCancelled else {
                    telemetryLogger.error("Failed to cancel bolus")
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump failed to cancel bolus",
                            comment: "Message when bolus could not be cancelled"
                        ),
                        request: request,
                        response: response
                    )
                }

                // Allow the Mobi to store the bolus in storage
                Thread.sleep(forTimeInterval: .seconds(2))

                // Query the pump for the actual delivered volume before clearing state
                active.dose.deliveredUnits = self.queryLastBolusDeliveredVolume(transport: transport, bolusId: active.id) ?? 0
                let canceledDose = active.dose.toDoseEntry(endDate: Date.now)

                // Clean up bolus tracking state (mirrors handleBolusResponse completion path)
                self.telemetryScheduler.cancelAll()
                self.bolusProgressReport = nil
                self.activeBolus.value = nil

                var events = getActivePumpEvents()
                events
                    .append(
                        NewPumpEvent
                            .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, date: canceledDose.startDate)
                    )

                self.state.lastReconciliation = Date.now
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                completion(.failure(.communication(pumpError)))
            }
        }
    }

    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        telemetryLogger.info("Setting temp basal at \(unitsPerHour)U/hr for \(duration)s")
        guard !isControlIQModeActive else {
            telemetryLogger.warning("[enactTempBasal] Blocked: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        guard let transport = pairedTransport else {
            telemetryLogger.error("Pump not connected...")
            completion(.communication(PumpCommError.pumpNotConnected))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let baselineRate = self.getScheduledBasalRate()
                guard baselineRate > 0 else {
                    self.telemetryLogger.error("No scheduled basal rate present or is 0, cannot enact temp basal")
                    throw PumpCommError.invalidScheduledBasalRate
                }

                // Query pump's current temp basal state, in case there is an active temp basal we don't have in our own state
                let currentTempRate: TempRateResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: TempRateRequest(),
                    expecting: TempRateResponse.self
                )

                if currentTempRate.active {
                    let response: StopTempRateResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: StopTempRateRequest(),
                        expecting: StopTempRateResponse.self
                    )

                    guard response.isStatusOK else {
                        self.telemetryLogger.error("Failed to cancel temp basal - status: \(response.status)")
                        throw PumpCommError.errorResponse(
                            context: String(
                                localized: "Pump failed to cancel temp basal",
                                comment: "Message when pump rejects request to stop temp rate"
                            ),
                            request: StopTempRateRequest(),
                            response: response
                        )
                    }

                    telemetryLogger.info("Canceled running temp basal!")
                }

                let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)
                let absoluteRate = self
                    .roundToSupportedBasalRate(unitsPerHour: Double(baselineRate * (Double(percent) / 100)))

                if duration < .ulpOfOne || percent == 100 {
                    // We only needed to cancel any current temp basal
                    let dose = UnfinalizedDose(
                        basalRate: baselineRate,
                        insulinType: state.insulinType,
                        startDate: Date.now
                    )
                    var events = self.getActivePumpEvents(endDate: dose.startDate)
                    events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))

                    state.basalDose = dose
                    state.lastReconciliation = Date.now
                    self.notifyDelegateStateUpdated()
                    self.emitPumpEvents(events)
                    completion(nil)
                    return
                }

                if absoluteRate < unitsPerHour {
                    self.telemetryLogger
                        .warning(
                            "Temp basal percentage limit reached: can only set \(absoluteRate)U/hr instead of requested \(unitsPerHour)U/hr"
                        )
                }

                let request = SetTempRateRequest(minutes: Int(duration.minutes), percent: percent)
                let response: SetTempRateResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: request,
                    expecting: SetTempRateResponse.self
                )

                if !response.isStatusOK {
                    self.telemetryLogger.error("enactTempBasal: SetTempRateResponse returned error status: \(response.status)")
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump failed to cancel temp basal",
                            comment: "Message when pump rejects request to stop temp rate"
                        ),
                        request: request,
                        response: response
                    )
                }

                let dose = UnfinalizedDose(
                    tempRate: absoluteRate,
                    duration: duration,
                    automatic: true,
                    insulinType: state.insulinType,
                )
                var events = self.getActivePumpEvents(endDate: dose.startDate)
                events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(), date: dose.startDate))

                state.basalDose = dose
                state.lastReconciliation = dose.startDate

                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)

                telemetryLogger.info("Temp basal enacted!")
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
        telemetryLogger.info("Suspend Insulin Delivery...")

        guard let transport = pairedTransport else {
            telemetryLogger.error("Pump not connected...")
            completion(PumpCommError.pumpNotConnected)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let currentTempRate: TempRateResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: TempRateRequest(),
                    expecting: TempRateResponse.self
                )

                if currentTempRate.active {
                    _ = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: StopTempRateRequest()
                    )
                }

                let response: SuspendPumpingResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: SuspendPumpingRequest(),
                    expecting: SuspendPumpingResponse.self
                )

                guard response.status == 0 else {
                    telemetryLogger.error("Pump rejected suspend delivery...")
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump failed to suspend delivery",
                            comment: "Message when pump rejects request to suspend insulin delivery"
                        ),
                        request: SuspendPumpingRequest(),
                        response: response
                    )
                }

                let suspendDose = UnfinalizedDose(suspendStartTime: Date.now)
                var events = self.getActivePumpEvents(endDate: suspendDose.startDate)
                events.append(NewPumpEvent.suspend(dose: suspendDose.toDoseEntry(), date: suspendDose.startDate))

                state.basalDose = suspendDose
                state.lastReconciliation = Date.now

                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)

                telemetryLogger.info("Insulin Delivery Suspended!")
                completion(nil)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                completion(pumpError)
            }
        }
    }

    public func resumeDelivery(completion: @escaping (_ error: Error?) -> Void) {
        telemetryLogger.info("Resume Insulin Delivery...")

        guard let transport = pairedTransport else {
            telemetryLogger.error("Pump not connected")
            completion(PumpCommError.pumpNotConnected)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let response: ResumePumpingResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: ResumePumpingRequest(),
                    expecting: ResumePumpingResponse.self
                )

                guard response.status == 0 else {
                    telemetryLogger.error("Pump rejected resume delivery...")
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Pump failed to resume delivery",
                            comment: "Message when pump rejects request to resume insulin delivery"
                        ),
                        request: ResumePumpingRequest(),
                        response: response
                    )
                }

                let dose = UnfinalizedDose(resumeStartTime: Date.now, insulinType: state.insulinType)
                let events = [
                    NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)
                ]

                state.basalDose = dose
                state.lastReconciliation = Date.now
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)

                telemetryLogger.info("Insulin Delivery Resumed!")
                completion(nil)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                completion(pumpError)
            }
        }
    }

    public func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void
    ) {
        guard !scheduleItems.isEmpty else {
            delegateQueue.async {
                completion(.failure(PumpManagerError.configuration(nil)))
            }
            return
        }

        guard let transport = pairedTransport else {
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completion(.failure(PumpManagerError.communication(error)))
            return
        }

        let sortedItems = scheduleItems.sorted { $0.startTime < $1.startTime }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Fetch current profile data using IDPManager
                let idpManager = IDPManager()

                // Fetch all IDP data until complete
                while !idpManager.isComplete {
                    let messages = idpManager.nextMessages()
                    if messages.isEmpty, !idpManager.isComplete {
                        throw PumpCommError.requestConstructionFailed(
                            reason: "Invalid IDPManager state in syncBasalRateSchedule"
                        )
                    }
                    for message in messages {
                        let response = try self.pumpComm.sendMessage(
                            transport: transport,
                            message: message
                        )
                        idpManager.processMessage(response)
                    }
                }

                if idpManager.getProfiles().isEmpty == true {
                    self.telemetryLogger.info("No profiles in IDPManager, creating initial profile for Trio")
                    // TODO(jwoglom): read correct profile defaults
                    let message = idpManager.createNewProfileMessage(
                        profileName: "TandemKitProfile",
                        defaultCarbRatio: 10,
                        defaultBasalRateUnits: scheduleItems.first?.value ?? 0,
                        defaultTargetBG: 110,
                        defaultISF: 40,
                        defaultInsulinDurationMinutes: 240,
                        profileCarbEntryEnabled: false
                    )
                    let newlyCreatedProfile = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: message
                    )

                    guard let newlyCreatedProfile = newlyCreatedProfile as? CreateIDPResponse else {
                        throw PumpCommError
                            .requestConstructionFailed(
                                reason: "No active profile found and got unexpected response creating initial profile"
                            )
                    }

                    guard newlyCreatedProfile.isStatusOK else {
                        throw PumpCommError
                            .requestConstructionFailed(reason: "No active profile found and failed to create initial profile")
                    }

                    self.telemetryLogger
                        .info("Created initial IDP profile with ID \(String(describing: newlyCreatedProfile.newIdpId))")

                    // Return to step 1: Reset idpManager
                    idpManager.clear()

                    // Fetch all IDP data until complete
                    while !idpManager.isComplete {
                        let messages = idpManager.nextMessages()
                        for message in messages {
                            let response = try self.pumpComm.sendMessage(
                                transport: transport,
                                message: message
                            )
                            idpManager.processMessage(response)
                        }
                    }
                }

                // Step 2: Get the active profile
                guard let activeProfile = idpManager.getActiveProfile() else {
                    throw PumpCommError.requestConstructionFailed(reason: "No active profile found")
                }

                // Step 3: Get current segments to preserve non-basal fields
                let currentSegments = activeProfile.getSegments()

                // Step 4: Build modify requests for each new basal schedule item
                var modifyRequests: [SetIDPSegmentRequest] = []

                for (index, scheduleItem) in sortedItems.enumerated() {
                    let startMinutes = Int((scheduleItem.startTime / 60.0).rounded())
                    let basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())

                    if index < currentSegments.count {
                        // Check if existing segment needs modification
                        let currentSegment = currentSegments[index]
                        let needsUpdate = currentSegment.profileStartTime != startMinutes ||
                            currentSegment.profileBasalRate != basalMilliunits

                        if needsUpdate {
                            let segment = currentSegment
                            segment.profileStartTime = startMinutes
                            segment.profileBasalRate = basalMilliunits
                            let request = activeProfile.modifySegmentMessage(segment: segment)
                            modifyRequests.append(request)
                        }
                    } else {
                        // Create new segment with default values from first segment
                        let firstSegment = currentSegments.first!
                        let request = activeProfile.createSegmentMessage(
                            profileStartTime: startMinutes,
                            profileBasalRate: basalMilliunits,
                            profileCarbRatio: firstSegment.profileCarbRatio,
                            profileTargetBG: Int(firstSegment.profileTargetBG),
                            profileISF: firstSegment.profileISF
                        )
                        modifyRequests.append(request)
                    }
                }

                // Step 5: If we have fewer items than current segments, delete extra segments
                if sortedItems.count < currentSegments.count {
                    for i in sortedItems.count ..< currentSegments.count {
                        if i > 0 { // Can't delete segment 0
                            let deleteRequest = activeProfile.deleteSegmentMessage(segment: currentSegments[i])
                            modifyRequests.append(deleteRequest)
                        }
                    }
                }

                // Step 6: Send all modification requests
                for request in modifyRequests {
                    let response: SetIDPSegmentResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: request,
                        expecting: SetIDPSegmentResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(
                            context: String(
                                localized: "Error syncing basal rates: Pump rejected SetIDPSegment",
                                comment: "Message when pump rejects SetIDPSegment"
                            ),
                            request: request,
                            response: response
                        )
                    }
                }

                let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: TimeZone.current) ?? state.basalRateSchedule

                var managerState = self.state
                managerState.basalRateSchedule = schedule
                managerState.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
                self.state = managerState

                self.notifyDelegateStateUpdated()
                self.delegateQueue.async {
                    completion(.success(schedule))
                }
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.notifyPumpManagerDelegateOfError(pumpError)
                telemetryLogger.error("Received error during basal sync: \(pumpError.errorDescription ?? "")")
                completion(.failure(PumpManagerError.communication(pumpError)))
            }
        }
    }

    public func syncDeliveryLimits(
        limits deliveryLimits: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    ) {
        guard let transport = pairedTransport else {
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            delegateQueue.async {
                completion(.failure(PumpManagerError.communication(error)))
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let appliedLimits: DeliveryLimits = try self.pumpComm.performOnCommandQueue {
                    let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
                    var appliedLimits = DeliveryLimits(maximumBasalRate: nil, maximumBolus: nil)

                    if let maxBasal = deliveryLimits.maximumBasalRate?.doubleValue(for: hkUnit) {
                        let milliunits = Int((maxBasal * 1000.0).rounded())
                        let request = SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits)
                        let response: SetMaxBasalLimitResponse = try self.pumpComm.sendMessage(
                            transport: transport,
                            message: request,
                            expecting: SetMaxBasalLimitResponse.self
                        )

                        guard response.status == 0 else {
                            throw PumpCommError.errorResponse(
                                context: String(
                                    localized: "Error setting max basal limit",
                                    comment: "Message when pump rejects SetMaxBasalLimit"
                                ),
                                request: request,
                                response: response
                            )
                        }

                        appliedLimits.maximumBasalRate = HKQuantity(unit: hkUnit, doubleValue: maxBasal)
                    }

                    if let maxBolus = deliveryLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit()) {
                        let milliunits = Int((maxBolus * 1000.0).rounded())
                        let request = SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits)
                        let response: SetMaxBolusLimitResponse = try self.pumpComm.sendMessage(
                            transport: transport,
                            message: request,
                            expecting: SetMaxBolusLimitResponse.self
                        )

                        guard response.status == 0 else {
                            throw PumpCommError.errorResponse(
                                context: String(
                                    localized: "Error setting max bolus limit",
                                    comment: "Message when pump rejects SetMaxBolusLimit"
                                ),
                                request: request,
                                response: response
                            )
                        }

                        appliedLimits.maximumBolus = HKQuantity(unit: HKUnit.internationalUnit(), doubleValue: maxBolus)
                    }

                    return appliedLimits
                }

                let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
                var managerState = self.state
                managerState.settings.maxTempBasalRate = appliedLimits.maximumBasalRate?.doubleValue(for: hkUnit)
                managerState.settings.maxBolus = appliedLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit())
                self.state = managerState

                self.notifyDelegateStateUpdated()

                self.delegateQueue.async {
                    completion(.success(appliedLimits))
                }
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
        telemetryLogger.info("Syncing pump time")

        guard let transport = pairedTransport else {
            telemetryLogger.error("Pump not connected...")
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            delegateQueue.async {
                completion(.failure(PumpManagerError.communication(error)))
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let epoch = Dates.fromInstantToJan12008EpochSeconds(Date.now)
                let request = ChangeTimeDateRequest(tandemEpochTime: UInt32(epoch))
                let response: ChangeTimeDateResponse = try pumpComm.sendMessage(
                    transport: transport,
                    message: request,
                    expecting: ChangeTimeDateResponse.self
                )

                if !response.isStatusOK {
                    telemetryLogger.error("Pump time sync failed, status NOK!")

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
            } catch {
                telemetryLogger.error("Failed to sync pump time: \(error.localizedDescription)")

                let pumpError = PumpCommError.other
                completion(.failure(PumpManagerError.communication(pumpError)))
            }
        }
    }

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        telemetryLogger.debug("Preparing for pump deactivation – tearing down transport")
        disconnect()
        tandemPump.stopScanning()
        targetPeripheralIdentifier = nil
        inScanningMode.value = false

        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }

    func setPumpSound(request: SetPumpSoundsRequest) {
        guard let transport = telemetryTransportIfReady(for: .sounds) else {
            telemetryLogger.error("Transport not available for sound telemetry")
            return
        }

        do {
            _ = try pumpComm.sendMessage(
                transport: transport,
                message: request,
                expecting: SetPumpSoundsResponse.self
            )

            // Allow the patch to set values
            Thread.sleep(forTimeInterval: .seconds(1))
            fetchGlobalPumpSettings(transport: transport)
        } catch {
            telemetryLogger.error("Failed to pump sounds: \(error.localizedDescription)")
        }
    }

    // MARK: - Play Sound

    func playSound() {
        guard let transport = pairedTransport else {
            telemetryLogger.error("Transport not available for play sound")
            return
        }

        do {
            _ = try pumpComm.sendMessage(
                transport: transport,
                message: PlaySoundRequest(),
                expecting: PlaySoundResponse.self
            )
        } catch {
            telemetryLogger.error("Failed to play sound: \(error.localizedDescription)")
        }
    }

    // MARK: - Alert Snooze

    func setAlertSnooze(enabled: Bool, durationMins: Int) {
        guard let transport = pairedTransport else {
            telemetryLogger.error("Transport not available for alert snooze")
            return
        }

        do {
            let response: SetPumpAlertSnoozeResponse = try pumpComm.sendMessage(
                transport: transport,
                message: SetPumpAlertSnoozeRequest(snoozeEnabled: enabled, snoozeDurationMins: durationMins),
                expecting: SetPumpAlertSnoozeResponse.self
            )

            guard response.isStatusOK else {
                telemetryLogger.error("Failed to set alert snooze: status \(response.status)")
                return
            }

            var managerState = state
            managerState.alertSnoozeEnabled = enabled
            managerState.alertSnoozeDuration = TimeInterval(minutes: Double(durationMins))
            state = managerState
            notifyDelegateStateUpdated()

            telemetryLogger.info("Alert snooze set: enabled=\(enabled), duration=\(durationMins)m")
        } catch {
            telemetryLogger.error("Failed to set alert snooze: \(error.localizedDescription)")
        }
    }

    // MARK: - Quick Bolus Settings

    func setQuickBolusSettings(enabled: Bool, mode: QuickBolusMode, increment: QuickBolusIncrement) {
        guard let transport = pairedTransport else {
            telemetryLogger.error("Transport not available for quick bolus settings")
            return
        }

        do {
            let response: SetQuickBolusSettingsResponse = try pumpComm.sendMessage(
                transport: transport,
                message: SetQuickBolusSettingsRequest(enabled: enabled, mode: mode, increment: increment),
                expecting: SetQuickBolusSettingsResponse.self
            )

            guard response.isStatusOK else {
                telemetryLogger.error("Failed to set quick bolus settings: status \(response.status)")
                return
            }

            Thread.sleep(forTimeInterval: .seconds(1))
            fetchGlobalPumpSettings(transport: transport)
        } catch {
            telemetryLogger.error("Failed to set quick bolus settings: \(error.localizedDescription)")
        }
    }
}

// MARK: - TandemPumpDelegate Conformance

extension TandemPumpManager: TandemPumpDelegate {
    public func tandemPump(
        _: TandemPump,
        shouldConnect peripheral: CBPeripheral,
        advertisementData _: [String: Any]?
    ) -> Bool {
        // If a target peripheral is set, only connect to that specific device
        if let targetIdentifier = targetPeripheralIdentifier {
            return peripheral.identifier == targetIdentifier
        }
        // Otherwise, do not connect
        return false
    }

    public func tandemPump(
        _: TandemPump,
        didCompleteConfiguration peripheralManager: PeripheralManager
    ) {
        // Only create a new transport if we don't have one yet, or if the peripheral manager changed
        let needsNewTransport = transportLock.value == nil || activePeripheralManager !== peripheralManager

        if needsNewTransport {
            telemetryLogger.info("Creating new transport for peripheral manager")
            let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            updateTransport(transport)
        } else {
            telemetryLogger.info("Reusing existing transport - peripheral manager unchanged")
        }

        activePeripheralManager = peripheralManager
        peripheralManager.activityHandler = { [weak self] in
            self?.updateLastHeartbeatIfNeeded()
        }
        notificationRouter.start(with: peripheralManager, session: pumpComm.getSession())

        updateBLEHeartbeatPreference()
        scheduleInitialConnectionTimeoutCheck()
    }

    /// Schedule a 5-second post-initialization timeout check.
    ///
    /// After BLE initialization completes and startup messages are dispatched,
    /// this verifies that at least one response has been received. If no responses
    /// arrived within the window and no auth bootstrap is running, the pump is
    /// soft-disconnected so the connection can be retried automatically.
    /// This mirrors PumpX2's `checkIfInitialPumpConnectionEstablished()`.
    private func scheduleInitialConnectionTimeoutCheck() {
        // Reset counters for this connection attempt
        processedResponseMessages.value = 0
        initialConnectionTimeoutAttempts.value = 0

        scheduleNextInitialConnectionTimeout()
    }

    private func scheduleNextInitialConnectionTimeout() {
        // Cancel any previously scheduled check
        initialConnectionTimeoutWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let repliesReceived = self.processedResponseMessages.value
            let bootstrapRunning = self.sessionBootstrapInProgress.value
            let pairing = self.pairingInProgress.value
            let attempt = self.initialConnectionTimeoutAttempts.value

            if repliesReceived > 0 {
                self.telemetryLogger.info(
                    "InitialConnectionTimeout: received \(repliesReceived) response(s) – connection healthy"
                )
            } else if pairing {
                // JPAKE handshake is in progress (first SwiftECC round can take >10s).
                // Do not disconnect — pairing manages its own lifecycle.
                self.telemetryLogger.info(
                    "InitialConnectionTimeout: pairing in progress – skipping disconnect"
                )
            } else if bootstrapRunning, attempt < self.initialConnectionTimeoutMaxAttempts {
                self.initialConnectionTimeoutAttempts.value += 1
                self.telemetryLogger.info(
                    "InitialConnectionTimeout: auth bootstrap still in progress (attempt \(attempt + 1)/\(self.initialConnectionTimeoutMaxAttempts)) – extending timeout"
                )
                self.scheduleNextInitialConnectionTimeout()
                return
            } else {
                self.telemetryLogger.error(
                    "InitialConnectionTimeout: no responses received (bootstrap=\(bootstrapRunning), attempt=\(attempt)) – soft disconnecting for retry"
                )
                self.tandemPump.softDisconnect()
            }
            self.initialConnectionTimeoutWork = nil
        }

        initialConnectionTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    public func tandemPump(
        _: TandemPump,
        didDiscoverDevice peripheral: CBPeripheral,
        advertisementData: [String: Any]?,
        rssi: NSNumber
    ) {
        if inScanningMode.value == true {
            let device = TandemPumpScan(
                bleIdentifier: peripheral.identifier.uuidString,
                name: peripheral.name ?? "Unknown",
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: rssi
            )

            notifyScanDeviceDidChange(device)
        } else if inScanningMode.value == false {
            configureDeliveryActions(true)
            telemetryLogger
                .info(
                    "[tandemPump didDiscoverDevice] expected pumpComm.pumpPeripheralUuid=\(String(describing: pumpComm.pumpPeripheralUuid))"
                )
            if peripheral.identifier.uuidString == pumpComm.pumpPeripheralUuid {
                telemetryLogger.info("[tandemPump didDiscoverDevice] set targetPeripheralIdentifier")
                targetPeripheralIdentifier = peripheral.identifier
            }
        }
    }

    public func tandemPump(
        _: TandemPump,
        didDisconnectWithError error: Error?
    ) {
        telemetryLogger.error("Pump disconnected with error: \(String(describing: error))")

        // Cancel any pending initial connection timeout check
        initialConnectionTimeoutWork?.cancel()
        initialConnectionTimeoutWork = nil
        processedResponseMessages.value = 0
        initialConnectionTimeoutAttempts.value = 0

        if let manager = activePeripheralManager {
            notificationRouter.stop(with: manager)
            activePeripheralManager = nil
        }

        updateTransport(nil)

        if isOnboarded {
            telemetryLogger.debug("Pump disconnected – restarting scan to reconnect")
            tandemPump.startScanning()
        }
    }
}

// MARK: - PumpCommDelegate Conformance

extension TandemPumpManager: PumpCommDelegate {
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
                self.telemetryLogger.warning("No pump delegate, not notifying...")
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

    public func pumpComm(_: PumpComm, didChange pumpState: PumpState) {
        // Update the stored state when pump state changes (e.g., after pairing)
        state.pumpState = pumpState
        notifyDelegateStateUpdated()

        pumpComm.syncPumpState(pumpState)
        if pumpState.valid {
            needsSessionInitialization.value = false
        }

        // Update pairing artifacts so messages will be signed with the derived secret
        updatePairingArtifacts(with: pumpState)
    }

    public func pumpComm(
        _: PumpComm,
        didReceive message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    ) {
        processedResponseMessages.value += 1
        initialConnectionTimeoutWork?.cancel()
        initialConnectionTimeoutWork = nil

        notificationLogger
            .debug(
                "[notification] Received \(String(describing: type(of: message))) opCode=\(metadata?.opCode ?? type(of: message).props.opCode) characteristic=\(characteristic.prettyName) txId=\(txId)"
            )

        switch message {
        case let battery as CurrentBatteryAbstractResponse:
            handleBatteryResponse(battery, source: .notification)
        case let insulin as InsulinStatusResponse:
            handleReservoirResponse(insulin, source: .notification)
        case let homeScreenResponse as HomeScreenMirrorResponse:
            handleHomeScreenMirrorResponse(homeScreenResponse, source: .notification)
        case let bolus as CurrentBolusStatusResponse:
            handleBolusResponse(bolus, source: .notification)
        case let timeSinceReset as TimeSinceResetResponse:
            handleTimeSinceResetResponse(timeSinceReset, source: .notification)
        case let pumpGlobal as PumpGlobalsResponse:
            handleGlobalPumpSettingsResponse(pumpGlobal, source: .notification)
        case let alertResponse as AlertStatusResponse:
            handleAlertResponse(alertResponse)
        case let fillTubingState as FillTubingStateStreamResponse:
            handleFillTubingStateStream(fillTubingState)
        default:
            if let meta = metadata {
                notificationLogger.debug("[notification] Ignoring \(meta.name) on \(characteristic.prettyName)")
            } else {
                notificationLogger.debug("[notification] Ignoring message type=\(String(describing: type(of: message)))")
            }
        }
    }

    public func pumpComm(_: PumpComm, didReceiveQualifyingEvents events: Set<QualifyingEvent>) {
        notificationLogger.info("[notification] Received qualifying events: \(events)")

        // Fetch suggested status messages for these events on a background queue,
        // routing through pumpComm.sendMessage so they go through the serial command queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let handlers = QualifyingEvent.groupSuggestedHandlers(events)
            self.notificationLogger.debug("[notification] Fetching \(handlers.count) status messages for qualifying events")

            guard let transport = self.pairedTransport else {
                self.notificationLogger.warning("[notification] No transport available for qualifying event handler")
                return
            }

            do {
                try self.pumpComm.performOnCommandQueue {
                    for message in handlers {
                        do {
                            let response = try self.pumpComm.sendMessage(transport: transport, message: message)
                            let metadata = MessageRegistry.metadata(for: response)

                            // Process the response through the normal notification handler
                            self.pumpComm(
                                self.pumpComm,
                                didReceive: response,
                                metadata: metadata,
                                characteristic: .CURRENT_STATUS_CHARACTERISTICS,
                                txId: 0
                            )
                        } catch {
                            self.notificationLogger.error("[notification] Failed to fetch handler for qualifying event: \(error)")
                        }
                    }
                }
            } catch {
                self.notificationLogger.error("[notification] Qualifying event handler failed: \(error)")
            }
        }
    }

    public func pumpComm(_: PumpComm, didEncounterFault event: PumpCommFaultEvent) {
        telemetryLogger
            .error(
                "Pump fault code=\(event.rawCode) category=\(event.category) attempt=\(event.attempt) willRetry=\(event.willRetry)"
            )

        if !event.willRetry {
            notifyPumpManagerDelegateOfError(.pumpFault(event: event))
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
    func releaseBolusPermission(transport: PumpMessageTransport, bolusId: Int) {
        do {
            let response: BolusPermissionReleaseResponse = try pumpComm.sendMessage(
                transport: transport,
                message: BolusPermissionReleaseRequest(bolusID: bolusId),
                expecting: BolusPermissionReleaseResponse.self
            )

            if response.status != 0 {
                telemetryLogger.error("Failed to release bolus permission for id \(bolusId) with status \(response.status)")
            }
        } catch {
            telemetryLogger.error("Error releasing bolus permission for id \(bolusId): \(String(describing: error))")
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
