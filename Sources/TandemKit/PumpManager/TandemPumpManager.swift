import Combine
import CoreBluetooth
import Dispatch
import Foundation
import HealthKit
import LoopKit
#if canImport(UIKit)
import UIKit
#endif

public class TandemPumpManager: PumpManager, Pluggable {
    public static var pluginIdentifier: String = "TandemPumpManager"

    public var localizedTitle: String = "Tandem mobi"
    public static var managerIdentifier: String = "Tandem"
    public typealias RawStateValue = [String: Any]

    let bluetooth: PumpBluetoothConnection

    // Tandem Mobi and t:slim X2: max 16 basal segments within a profile
    public static var onboardingMaximumBasalScheduleEntryCount: Int = 16

    // Tandem Mobi and t:slim X2: 0.0u, then 0.1 - 15.00u/hr in 0.01u chunks
    public static var onboardingSupportedBasalRates: [Double] = TandemPumpCapabilities.supportedBasalRates

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
    public let fillCannulaStateStream = PassthroughSubject<FillCannulaStateStreamResponse, Never>()
    public let changeCartridgeStateStream = PassthroughSubject<EnterChangeCartridgeModeStateStreamResponse, Never>()
    public let detectingCartridgeStateStream = PassthroughSubject<DetectingCartridgeStateStreamResponse, Never>()
    public let historyLogStream = PassthroughSubject<HistoryLogStreamResponse, Never>()

    /// Session-scoped working memory of raw history logs, fed by `historyLogStream` (see
    /// `TandemPumpManager+HistoryStore.swift`).
    ///
    /// Deliberately in-memory (#232): the pump-manager layer stays storage-free — durable dose
    /// storage is the host app's job — so this holds only what has streamed in since launch.
    /// Anything that must survive a relaunch belongs in `state`, not here.
    public let historyLogStore: HistoryLogStore = InMemoryHistoryLogStore()
    private var historyLogStoreSubscription: AnyCancellable?
    // Guards lastHistoryLogPruneAt: inserts arrive on the BLE notification path while tests and
    // future scheduler hooks may prune from other threads.
    let historyLogPruneLock = NSLock()
    var lastHistoryLogPruneAt: Date?

    internal var bolusProgressReport: TandemDoseProgressReporter?
    private let silentToneManager = TandemSilentToneManager()
    var notificationBundle = NotificationBundle()

    // Independent queue on which command watchdog timeouts fire. It must NOT be the BLE command
    // queue (otherwise a wedged command could starve its own watchdog), so a dedicated queue is used.
    let watchdogQueue = DispatchQueue(label: "com.jwoglom.TandemKit.commandWatchdog")
    // Backstop timeout for pump commands. This MUST stay comfortably larger than the worst-case
    // real command duration, otherwise it could report a spurious failure for a command that is
    // still in progress — and for a bolus a false failure can prompt the loop to retry, risking a
    // double dose. Worst case ≈ connectTimeout (30s) + a few bounded write round-trips, each of
    // which is bounded by TandemPeripheralManager.responseTimeout (30s), so a command always
    // self-completes via the lower-level bounded waits well before this fires; the watchdog is
    // purely a last-resort guarantee that the loop receives exactly one result.
    // (Follow-up: on a bolus timeout, surfacing uncertain delivery would be safer than a clean
    // failure. Tracked separately.) Exposed (internal) so tests can override it with a short value.
    var commandWatchdogTimeout: DispatchTimeInterval = .seconds(180)

    // Syncs queued or running on the command queue. Loop polls every ~5 minutes, and a sync
    // against an unresponsive pump spends that long working through bounded write timeouts, so
    // the polls have to be told to stand down rather than stack up behind it — as would every
    // user command sharing that queue. Guarded because syncs start and finish on different queues.
    private let syncStateLock = NSLock()
    private var inFlightSyncs = 0

    #if canImport(UIKit)
    @objc func appMovedToBackground() {
        if state.useSilentTones {
            logger.info("Starting silent tones")
            silentToneManager.startBackgroundTask()
        }
    }

    @objc func appMovedToForeground() {
        silentToneManager.stopBackgroundTask()
    }
    #endif

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
            hasDelegateQueue = newValue != nil
            deliverStateMissedByTheDelegate()
        }
    }

    /// `pumpDelegate.queue` reads back as `.main` until the host sets one, and the host's delegate
    /// methods assert they are on its own queue, so "is there a queue" has to be tracked here
    /// rather than inferred from the delegate holder.
    private var hasDelegateQueue = false

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

    public convenience init(state: TandemPumpManagerState) {
        self.init(state: state, bluetooth: TandemBluetoothManager())
    }

    /// Designated initializer. Tests inject a stub `bluetooth` here to drive command sequences
    /// without CoreBluetooth; production goes through `init(state:)`.
    init(state: TandemPumpManagerState, bluetooth: PumpBluetoothConnection) {
        self.state = state
        oldState = TandemPumpManagerState(rawValue: state.rawValue)
        self.bluetooth = bluetooth
        bluetooth.pumpManager = self

        // Every history log that streams in — telemetry, viewer fetches, probes — lands in the
        // session store, so later readers within the session don't go back to the pump for it.
        historyLogStoreSubscription = historyLogStream.sink { [weak self] response in
            self?.storeHistoryLogs(response.historyLogs)
        }

        #if canImport(UIKit)
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
        #endif
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
            deliverStateMissedByTheDelegate()
        }
    }

    /// Catches the host app up on anything that only gets pushed once.
    ///
    /// The manager runs before the host adopts it — pairing finishes with a full `syncPumpData`,
    /// and polls can fire while a relaunching app is still wiring itself up — so reads land with
    /// no delegate to hand them to. Called from both the delegate and the queue setter because
    /// the host sets them one after the other (Trio sets the delegate first) and `notify` needs
    /// both; whichever lands second does the work.
    private func deliverStateMissedByTheDelegate() {
        guard pumpDelegate.delegate != nil, hasDelegateQueue else { return }

        // The status is re-sent on every state change anyway, but sending it now means the host
        // does not show a blank battery/basal until something happens to move it.
        notifyDelegateStateUpdated()
        flushPendingReservoirReading()
    }

    /// Auto-acknowledgement of basal min/max alerts is always on and has no user-facing control:
    /// oref sets zero basal rates as a matter of course, and the pump would alert on each one.
    /// This remains only so tests can exercise the disabled path — do not expose it to the UI.
    internal func configureAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        state.autoAcknowledgeBasalAlerts = enabled
        notifyDelegateStateUpdated()

        logger.info("Auto-acknowledge basal alerts \(enabled ? "enabled" : "disabled")")
    }

    public func configureSilentMode(_ enabled: Bool) {
        state.useSilentTones = enabled
        notifyDelegateStateUpdated()

        logger.info("Heartbeat mode silent tones \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Feature Flags

    public func isFeatureEnabled(_ flag: TandemFeatureFlags.Flag) -> Bool {
        state.featureFlags[flag]
    }

    public func setFeatureFlag(_ flag: TandemFeatureFlags.Flag, enabled: Bool) {
        state.featureFlags[flag] = enabled
        notifyDelegateStateUpdated()

        logger.info("Feature flag \(flag.rawValue) \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        logger.info("Sync pump data...")

        if let lastSync = state.lastReconciliation, Date.now.timeIntervalSince(lastSync) < .minutes(4.5) {
            logger.warning("State already in sync: \(Date.now.timeIntervalSince(lastSync)) sec")
            completion?(lastSync)
            return
        }

        syncPumpData(onlyIfIdle: true, completion: completion)
    }

    /// Registers a sync as in flight. Returns false only when `onlyIfIdle` and one already is.
    private func beginSync(onlyIfIdle: Bool) -> Bool {
        syncStateLock.lock()
        defer { syncStateLock.unlock() }

        if onlyIfIdle, inFlightSyncs > 0 {
            return false
        }
        inFlightSyncs += 1
        return true
    }

    private func endSync() {
        syncStateLock.lock()
        inFlightSyncs -= 1
        syncStateLock.unlock()
    }

    /// - Parameter onlyIfIdle: stand down when a sync is already queued or running. Set by the
    ///   automatic poll; a sync the user asked for runs regardless.
    func syncPumpData(onlyIfIdle: Bool = false, completion: ((_ lastSync: Date?) -> Void)?) {
        guard beginSync(onlyIfIdle: onlyIfIdle) else {
            logger.warning("A sync is already in flight; not queueing another")
            completion?(state.lastReconciliation)
            return
        }

        // Layer 1 backstop: always hand the loop a lastSync, even if the layers below wedge.
        // Capture lastReconciliation in a local so the timeoutResult autoclosure doesn't reference
        // `self` — `self.state` here gets stripped by the Swiftformat build phase (redundantSelf),
        // which then fails to compile because the autoclosure escapes.
        let lastReconciliation = state.lastReconciliation
        let completion = watchdogged(timeoutResult: lastReconciliation) { completion?($0) }
        bluetooth.ensureConnected { error in
            // Cleared when the job ends, not when `completion` fires: the watchdog hands Loop a
            // result at 180s while these blocking reads are still holding the queue.
            defer { self.endSync() }

            if let error {
                self.logger.error("Failed to connect for sync: \(error.localizedDescription)")
                completion(self.state.lastReconciliation)
                return
            }

            let responsesBefore = self.bluetooth.responseCount

            let lastSettingsCheckedAt = self.state.lastSettingsCheckedAt
            if lastSettingsCheckedAt == nil || Date.now.timeIntervalSince(lastSettingsCheckedAt!) > .hours(24) {
                self.fetchControlIQStatus()
                self.fetchDeliveryLimits()
                self.fetchGlobalPumpSettings()
                self.fetchPumpInformation()

                // Same reason as lastSync below: stamping this after a pump that answered nothing
                // would suppress the next attempt for 24 hours.
                if self.bluetooth.responseCount > responsesBefore {
                    self.state.lastSettingsCheckedAt = Date.now
                }
            } else if !self.state.featureFlags.quickBolusButtonSupport {
                // The quick bolus button is confirmed off every cycle, which needs a fresh read.
                self.fetchGlobalPumpSettings()
            }

            self.enforceQuickBolusDisabled()

            self.fetchReservoirStatus()
            self.fetchBatteryStatus()
            self.fetchBolusStatus(fromSync: true)
            self.fetchBasalStatus()
            self.fetchNotifications()
            self.fetchTimeSinceReset()
            self.fetchCGMSessionStatus()

            // A connected link is not a working one: a session can stay up while every read times
            // out, and advancing lastSync then promises Loop a reconciliation that never happened.
            if self.bluetooth.responseCount > responsesBefore {
                self.state.lastReconciliation = Date.now
            } else {
                self.logger.error("Sync got no response from the pump; leaving lastSync where it was")
            }

            self.notifyDelegateStateUpdated()

            completion(self.state.lastReconciliation)
        }
    }

    public func setMustProvideBLEHeartbeat(_: Bool) {}

    /// Sends an arbitrary message to the pump and returns the decoded response, if any.
    /// Intended for the debug tools only, which pick a message by name and so have no static type
    /// to take a response from. The expected response type is resolved from the message registry's
    /// request→response association; a message with no association is refused and yields `nil`.
    public func sendDebugMessage(_ message: Message, completion: @escaping (Message?) -> Void) {
        bluetooth.ensureConnected { error in
            if error != nil {
                completion(nil)
                return
            }
            let expecting = MessageRegistry.metadata(for: message)?.associatedType ?? type(of: message)
            let response = self.bluetooth.writeUntyped(message, expecting: expecting)
            completion(response)
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

    /// Returns the reason `units` is not a deliverable bolus, or nil when it is.
    ///
    /// `settings.maxBolus` mirrors the delivery limit the host app last synced (see
    /// `syncDeliveryLimits`); when it has never been synced the limit is nil and only the
    /// positive-amount check applies.
    func validateBolusRequest(units: Double) -> TandemPumpManagerValidationError? {
        guard units > 0 else {
            return .invalidBolusAmount(requested: units)
        }

        if let maxBolus = state.settings.maxBolus, units > maxBolus {
            return .maximumBolusExceeded(requested: units, maximum: maxBolus)
        }

        return nil
    }

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        // Layer 1 backstop: guarantee the loop gets exactly one result even if the layers below wedge.
        let completion = watchdogged(timeoutResult: .communication(PumpCommError.pumpNotConnected), completion)
        logger.info("Enacting bolus - units \(units)U")

        if state.useControlIQ, activationType.isAutomatic {
            logger.warning("[enactBolus] Blocked automatic bolus: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        // The pump enforces its own max bolus limit (pushed down by syncDeliveryLimits via
        // SetMaxBolusLimitRequest), but check here too so an out-of-range request fails fast with a
        // specific error instead of being rejected mid-handshake as a generic permission denial.
        if let error = validateBolusRequest(units: units) {
            logger.error("[enactBolus] Rejected bolus request of \(units)U: \(error)")
            completion(.deviceState(error))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for bolus: \(error.localizedDescription)")
                completion(.communication(PumpCommError.pumpNotConnected))
                return
            }

            guard let permissionResponse = self.bluetooth.write(BolusPermissionRequest()) else {
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
            guard let initiateResponse = self.bluetooth.write(bolusRequest) else {
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

            let doseEntry = dose.toDoseEntry(isMutable: true)
            self.bolusProgressReport = TandemDoseProgressReporter(
                pumpManager: self,
                dose: doseEntry,
                activationType: activationType
            )

            self.state.bolusDose = dose
            self.state.bolusState = .initiating
            self.state.lastReconciliation = Date.now
            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(
                [NewPumpEvent.bolus(dose: doseEntry, units: units, date: dose.startDate)],
                replacePendingEvents: false
            )

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

            guard let response = self.bluetooth.write(CancelBolusRequest(bolusId: bolusId)) else {
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
        // Layer 1 backstop: guarantee the loop gets exactly one result even if the layers below wedge.
        let completion = watchdogged(timeoutResult: .connection(PumpCommError.pumpNotConnected), completion)
        let unitsPerHour = roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
        logger.info("Setting temp basal at \(unitsPerHour)U/hr for \(duration)s")

        guard !state.useControlIQ else {
            logger.warning("[enactTempBasal] Blocked: Control-IQ mode is active")
            completion(.deviceState(TandemPumpManagerValidationError.controlIQModeActive))
            return
        }

        if let bolusProgressReport, bolusProgressReport.isUnfinalized() {
            logger.warning("[enactTempBasal] Blocked: A bolus is still running")
            completion(.deviceState(TandemPumpManagerValidationError.bolusIsRunning))
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

            guard let currentBasal = self.bluetooth.write(CurrentBasalStatusRequest()) else {
                self.logger.error("Failed to fetch current temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            if currentBasal.basalType == .tempBasal {
                guard let stopCurrentRate = self.bluetooth.write(StopTempRateRequest()) else {
                    self.logger.error("Failed to stop temp rate")
                    completion(.communication(PumpCommError.noResponse))
                    return
                }

                guard stopCurrentRate.isStatusOK else {
                    self.logger.error("Failed to stop temp rate - Status: \(stopCurrentRate.status)")
                    completion(.communication(PumpCommError.invalidPacket))
                    return
                }

                self.logger.info("Current temp basal cancelled!")
            }

            let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)
            let absoluteRate = self
                .roundToSupportedBasalRate(unitsPerHour: Double(baselineRate * (Double(percent) / 100)))

            if duration < .ulpOfOne || percent == 100 {
                // We only needed to cancel any current temp basal
                // Qualifying events will handle state update
                self.logger.info("Enact completed! (no basal rate change)")

                let dose = UnfinalizedDose(
                    basalRate: self.getScheduledBasalRate(),
                    insulinType: self.state.insulinType,
                    startDate: Date.now
                )
                
                var events = self.getActivePumpEvents(endDate: dose.startDate)
                events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(isMutable: false), date: dose.startDate))

                self.state.basalDose = dose
                self.state.lastReconciliation = Date.now
                
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)

                completion(nil)
                return
            }

            let request = SetTempRateRequest(minutes: Int(duration.minutes), percent: percent)
            guard let response = self.bluetooth.write(request) else {
                self.logger.error("Failed to set temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard response.isStatusOK else {
                self.logger
                    .error(
                        "Failed to set temp rate - Status: \(response.status), percent: \(percent), duration: \(duration.minutes)min"
                    )
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
            events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true), date: dose.startDate))

            self.state.basalDose = dose
            self.state.lastReconciliation = dose.startDate

            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            self.logger.info("Temp basal enacted!")
            completion(nil)
        }
    }

    public func suspendDelivery(completion: @escaping (_ error: Error?) -> Void) {
        let completion = watchdogged(timeoutResult: PumpCommError.pumpNotConnected as Error?, completion)
        logger.info("Suspend Insulin Delivery...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }

            guard let currentTempResponse = self.bluetooth.write(TempRateRequest()) else {
                self.logger.error("Failed to get currentTempRate...")
                completion(PumpCommError.noResponse)
                return
            }
            if currentTempResponse.active {
                let stopResponse = self.bluetooth.write(StopTempRateRequest())
                if let stopResponse, stopResponse.isStatusOK {
                    self.logger.info("Current temp basal cancelled!")
                } else {
                    self.logger
                        .error(
                            "Failed to stop temp rate before suspending - Status: \(stopResponse?.status ?? -1)"
                        )
                }
            }

            let response = self.bluetooth.write(SuspendPumpingRequest())
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
        let completion = watchdogged(timeoutResult: PumpCommError.pumpNotConnected as Error?, completion)
        logger.info("Resume Insulin Delivery...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }

            completion(self.sendResumePumping())
        }
    }

    /// Resumes delivery, first clearing the pump's "resume pump" alarms if they are what stands
    /// in the way.
    ///
    /// While delivery is suspended the pump raises `RESUME_PUMP_ALARM`/`RESUME_PUMP_ALARM2` to
    /// tell the user insulin is not being delivered, and a resume can be refused while either is
    /// still unacknowledged. A user pressing "Resume Insulin Delivery" is already acting on what
    /// those alarms ask for, so when the first attempt fails we re-read the pump's notification
    /// state, acknowledge whichever of the two are active, and retry once — instead of making the
    /// user go clear them by hand from the notifications screen.
    ///
    /// Only those two alarms are acknowledged on the user's behalf. If neither is active, or the
    /// retry fails too, the original/retry error is surfaced so the caller still reports the
    /// failure. The sequence itself lives in `ResumeWithAlarmAcknowledgement`, which is where it is
    /// unit-tested; this method just binds it to the pump.
    func resumeDeliveryAcknowledgingResumeAlarms(completion: @escaping (_ error: Error?) -> Void) {
        let completion = watchdogged(timeoutResult: PumpCommError.pumpNotConnected as Error?, completion)
        logger.info("Resume Insulin Delivery (clearing resume-pump alarms if needed)...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }

            let sequence = ResumeWithAlarmAcknowledgement(
                sendResume: { self.sendResumePumping() },
                reloadNotifications: { self.fetchNotifications() },
                activeResumeAlarms: { self.notificationBundle.activeResumePumpAlarms() },
                acknowledgeAlarm: { alarm in
                    _ = self.acknowledgeNotification(type: .alarm, id: UInt32(alarm.rawValue))
                },
                log: { self.logger.info($0) }
            )

            completion(sequence.run())
        }
    }

    /// Sends a single `ResumePumpingRequest` and, on success, records the resume dose and notifies
    /// LoopKit. Returns nil on success or the error to report otherwise.
    ///
    /// Must be called while connected (i.e. inside `bluetooth.ensureConnected`).
    private func sendResumePumping() -> Error? {
        let response = bluetooth.write(ResumePumpingRequest())
        guard let response, response.status == 0 else {
            logger.error("Failed to Resume delivery - Status: \(response?.status ?? -1)")
            return PumpCommError.noResponse
        }

        let dose = UnfinalizedDose(
            resumeStartTime: Date.now,
            insulinType: state.insulinType
        )
        let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]

        state.basalDose = dose
        state.lastReconciliation = Date.now

        notifyDelegateStateUpdated()
        emitPumpEvents(events)

        logger.info("Insulin Delivery Resumed!")
        return nil
    }

    public func syncDeliveryLimits(
        limits: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    ) {
        let completion = watchdogged(timeoutResult: .failure(PumpCommError.pumpNotConnected), completion)
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
                guard let basalResponse = self.bluetooth.write(SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits)) else {
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

                guard let bolusResponse = self.bluetooth.write(SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits)) else {
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

            let response = self.bluetooth.write(EnterChangeCartridgeModeRequest())

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

            let response = self.bluetooth.write(ExitChangeCartridgeModeRequest())

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

            let response = self.bluetooth.write(EnterFillTubingModeRequest())

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

            let response = self.bluetooth.write(ExitFillTubingModeRequest())

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

            let response = self.bluetooth.write(FillCannulaRequest(primeSizeMilliUnits: Int(amount * 1000)))

            completion(response)
        }
    }

    /// Records a cannula / infusion-set change. Call after the user successfully fills the cannula.
    /// Tracks the date in state and reports a site-change pump event to the host app via the delegate.
    func recordSiteChange(at date: Date = Date.now) {
        logger.info("Recording site change (cannula fill) at \(date)")
        state.lastSiteChangeDate = date
        notifyDelegateStateUpdated()
        emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
    }

    /// Records a cartridge / reservoir change. Call after the user successfully changes the cartridge.
    /// Tracks the date in state and reports the change as a pump event to the host app via the delegate.
    func recordCartridgeChange(at date: Date = Date.now) {
        logger.info("Recording cartridge change at \(date)")
        state.lastCartridgeChangeDate = date
        notifyDelegateStateUpdated()
        emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
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
            guard let response = self.bluetooth.write(request) else {
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
                self.syncPumpData { _ in
                    completion(.success(()))
                }
            }
        }
    }

    func pairPump(code: String, peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        state.pumpState.pincode = code
        bluetooth.connect(peripheral, completion: completion)
    }

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        logger.debug("Preparing for pump deactivation – tearing down transport")
        bluetooth.deactivate()

        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }

    /// Forces a fresh connect and full status sync, skipping the freshness short-circuit in
    /// `ensureCurrentPumpData`. Used by the connection troubleshooter's reconnect button so the
    /// user can retry a wedged connection on demand. `completion` reports the resulting lastSync.
    public func attemptReconnect(completion: ((_ lastSync: Date?) -> Void)? = nil) {
        logger.info("Manual reconnect attempt")
        syncPumpData(completion: completion)
    }

    /// Clears the saved pairing/pump state (derived secret, server nonce, pincode, cached pump
    /// identity) so the next setup run pairs from scratch. `isOnboarded` becomes false once this
    /// runs. Used by the debug "Re-run Pump Setup" action, which intentionally breaks the state.
    public func deleteSavedPumpState() {
        logger.debug("Deleting saved pump state for re-setup")
        state.pumpState = PumpState()
        notifyDelegateStateUpdated()
    }

    func setPumpSound(request: SetPumpSoundsRequest, completion: @escaping () -> Void) {
        logger.info("Setting pump sounds...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sound settings: \(error.localizedDescription)")
                completion()
                return
            }

            _ = self.bluetooth.write(request)

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

            _ = self.bluetooth.write(PlaySoundRequest())
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

            guard let response = self.bluetooth.write(SetPumpAlertSnoozeRequest(snoozeEnabled: enabled, snoozeDurationMins: durationMins)) else {
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

            guard let response = self.bluetooth.write(SetQuickBolusSettingsRequest(enabled: enabled, mode: mode, increment: increment)) else {
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

    func getControlIQData(completion: @escaping (ControlIQInfoAbstractResponse?, ControlIQSleepScheduleResponse?) -> Void) {
        logger.info("Getting controlIQ info")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for getting controlIQ data: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }

            // Pumps at or below API 2.1 only answer the V1 request, so ask for the variant this pump
            // speaks rather than always asking for V2 and reporting nothing when it goes unanswered.
            let request = ControlIQInfoRequestBuilder.create(apiVersion: self.state.pumpState.apiVersion)
            let iqInfo = self.bluetooth.write(request) as? ControlIQInfoAbstractResponse

            let scheduleInfo = self.bluetooth.write(ControlIQSleepScheduleRequest())

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

            guard let response = self.bluetooth.write(SetModesRequest(command: mode)) else {
                self.logger.error("Failed to set controlIQ mode")
                completion(false)
                return
            }

            completion(response.isStatusOK)
        }
    }

    /// Applies a Control-IQ settings change, reporting the CGM status that follows it on success.
    ///
    /// Enabling Control-IQ requires a weight and total daily insulin the pump will accept; a pump on
    /// which Control-IQ has never been configured reports zeroes for both, and rejects a request
    /// carrying them. Those are checked here so the request never leaves the phone -- and, just as
    /// importantly, so a doomed request does not first cancel a running temp basal below.
    /// Disabling Control-IQ carries the same fields but does not depend on them, so it is not gated.
    func configureControlIQMode(
        _ request: ChangeControlIQSettingsRequest,
        completion: @escaping (Result<CGMStatusV2Response?, Error>) -> Void
    ) {
        logger.info("Configure controlIQ mode: \(request.enabled)")

        if request.enabled, let failure = ControlIQSettingsLimits.validate(
            weightLbs: request.weightLbs,
            totalDailyInsulinUnits: request.totalDailyInsulinUnits
        ) {
            let error = ControlIQConfigurationError(failure)
            logger.error("Refusing to enable ControlIQ: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for controlIQ mode: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if request.enabled, self.state.basalDose.type == .tempBasal {
                _ = self.bluetooth.write(StopTempRateRequest())

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

            guard let response = self.bluetooth.write(request) else {
                self.logger.error("Failed to change controlIQ mode")
                completion(.failure(ControlIQConfigurationError.noResponse))
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to change controlIQ mode - Status: \(response.status)")
                completion(.failure(ControlIQConfigurationError.pumpRejected(status: response.status)))
                return
            }

            let cgmResponse = self.bluetooth.write(CGMStatusV2Request())

            if let cgmResponse {
                self.updateCGMSessionState(from: cgmResponse)
            }

            // Pump accepted -- update local preference
            self.state.useControlIQ = request.enabled
            self.state.controlIQWeightLbs = request.weightLbs
            self.state.controlIQTotalDailyInsulin = request.totalDailyInsulinUnits
            self.notifyDelegateStateUpdated()

            self.logger.info("Algorithm mode set to \(request.enabled ? "Control-IQ" : "DIY")")

            // Refresh pump state to confirm ControlIQ status
            Thread.sleep(forTimeInterval: 1.0)
            self.syncPumpData { _ in
                completion(.success(cgmResponse))
            }
        }
    }

    /// Whether this pump's model and API version can be expected to handle `messageType`, so the UI
    /// can hide a control instead of offering a write the pump will never answer.
    func supports<T: Message>(_ messageType: T.Type) -> Bool {
        messageType.props.isSupported(
            pumpModel: state.pumpState.pumpModel,
            apiVersion: state.pumpState.apiVersion
        )
    }

    func setSleepSchedule(
        slot: Int,
        schedule: ControlIQSleepScheduleResponse.SleepSchedule,
        completion: @escaping (Bool) -> Void
    ) {
        logger.info("Setting sleep schedule")

        guard supports(SetSleepScheduleRequest.self) else {
            logger.error("Pump does not support setting sleep schedules")
            completion(false)
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sleep schedule: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let response = self.bluetooth.write(SetSleepScheduleRequest(
                    slot: slot,
                    schedule: schedule,
                    flag: 1
                )) else {
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

        guard let primaryDismissType = item.type.dismissType else {
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

            // 1. Acknowledge the primary. For a merged row (see
            //    `MergedNotificationGroup`) this is the group's primary member.
            guard self.acknowledgeNotification(type: primaryDismissType, id: item.notificationId) else {
                completion(false)
                return
            }

            // An ordinary (non-merged) row is done once its notification is acked.
            guard !item.mergedMembers.isEmpty else {
                // Refresh the bundle so the LoopKit alert reconciler retracts the
                // dismissed notification instead of waiting for the next poll.
                self.fetchNotifications()
                completion(true)
                return
            }

            // 2. Reload pump state so we can see which members the pump cleared on
            //    its own when the primary was acknowledged.
            self.fetchNotifications()

            // 3. Acknowledge any merged member the pump did NOT auto-clear. Members
            //    the pump already dropped are skipped, so we never dismiss a
            //    notification that is no longer present.
            var allAcknowledged = true
            var sentSecondaryAck = false
            for member in item.mergedMembers {
                guard self.notificationBundle.isActive(type: member.type, id: member.id) else {
                    continue
                }
                guard let memberDismissType = member.type.dismissType else {
                    continue
                }
                sentSecondaryAck = true
                if !self.acknowledgeNotification(type: memberDismissType, id: member.id) {
                    allAcknowledged = false
                }
            }

            // Reflect the extra acknowledgements in the bundle/state if we sent any.
            if sentSecondaryAck {
                self.fetchNotifications()
            }

            completion(allAcknowledged)
        }
    }

    /// Sends a single `DismissNotificationRequest` and reports whether the pump
    /// acknowledged it. Must be called while connected (e.g. inside
    /// `bluetooth.ensureConnected`).
    private func acknowledgeNotification(type: DismissNotificationRequest.NotificationType, id: UInt32) -> Bool {
        guard let response = bluetooth.write(DismissNotificationRequest(notificationType: type, notificationId: id)) else {
            logger.error("Failed to dismiss notification id=\(id) type=\(type)")
            return false
        }

        if !response.isStatusOK {
            logger.error("Failed to dismiss notification id=\(id) - Status: \(response.status)")
        }
        return response.isStatusOK
    }

    func getCGMStatus(completion: @escaping (CGMStatusV2Response?) -> Void) {
        logger.info("Fetching CGM status...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for CGM status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let response = self.bluetooth.write(CGMStatusV2Request())

            if let response {
                self.updateCGMSessionState(from: response)
            }

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

            guard let response = self.bluetooth.write(StopDexcomCGMSensorSessionRequest()) else {
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

            guard let sensorTypeResponse = self.bluetooth.write(SetSensorTypeRequest(sensorType: .dexcomG6)) else {
                self.logger.error("Failed to set Sensortype to G6")
                completion(false)
                return
            }

            guard sensorTypeResponse.isStatusOK else {
                self.logger.error("Failed to set Sensortype to G6 - Status: \(sensorTypeResponse.status)")
                completion(false)
                return
            }

            guard let transmitterResponse = self.bluetooth.write(SetG6TransmitterIdRequest(txId: txId)) else {
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
                guard let startSensorResponse = self.bluetooth.write(StartDexcomG6SensorSessionRequest(sensorCode: code)) else {
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

            guard let sensorTypeResponse = self.bluetooth.write(SetSensorTypeRequest(sensorType: .dexcomG7)) else {
                self.logger.error("Failed to set Sensortype to G7")
                completion(false)
                return
            }

            guard sensorTypeResponse.isStatusOK else {
                self.logger.error("Failed to set Sensortype to G7 - Status: \(sensorTypeResponse.status)")
                completion(false)
                return
            }

            guard let startG7 = self.bluetooth.write(SetDexcomG7PairingCodeRequest(pairingCode: code)) else {
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

    func handleQualifyingEvents(events: Set<QualifyingEvent>, completion: @escaping () -> Void) {
        logger.info("Received qualifying events: \(events)")

        let context = qualifyingEventContext
        for qualifyingEvent in events
            where QualifyingEventFetch.fetches(for: [qualifyingEvent], context: context).isEmpty {
            logger.info("Skipping event: \(qualifyingEvent)")
        }

        // Deduplicated across the batch, so an alert+alarm pair reloads the notification bundle
        // once rather than twice. QualifyingEventFetch derives this from the pumpX2-aligned
        // suggested handlers on QualifyingEvent.
        let fetches = QualifyingEventFetch.fetches(for: events, context: context)
        guard !fetches.isEmpty else {
            // Nothing to fetch (e.g. iobChange only) — don't spin up a command job just to
            // acknowledge; ack immediately.
            completion()
            return
        }

        // Run the status fetches as a serialized command job (via the single commandQueue) so
        // they can no longer race loop/therapy commands on the write path — this overlap was a
        // root cause of the wedged connection. ensureConnected returns on commandQueue, so the
        // fetches and the qualifying-event acknowledgement (completion) are fully serialized.
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to handle qualifying events: \(error.localizedDescription)")
                completion()
                return
            }

            for fetch in fetches {
                self.runFetch(fetch)
            }

            completion()
        }
    }

    /// The pump state the suggested handlers are selected against. PumpX2 reads the equivalent
    /// out of its global `PumpStateSupplier`.
    var qualifyingEventContext: QualifyingEventContext {
        QualifyingEventContext(
            apiVersion: state.pumpState.apiVersion,
            controlIQSupported: state.controlIQEnabled ?? false,
            inProgressBolusId: state.bolusDose?.bolusId
        )
    }

    private func runFetch(_ fetch: QualifyingEventFetch) {
        switch fetch {
        case .notifications:
            fetchNotifications()
        case .controlIQStatus:
            fetchControlIQStatus()
        case .basalStatus:
            fetchBasalStatus()
        case .bolusStatus:
            fetchBolusStatus(fromSync: false)
        case .reservoirStatus:
            fetchReservoirStatus()
        case .batteryStatus:
            fetchBatteryStatus()
        case .deliveryLimits:
            fetchDeliveryLimits()
        case .globalPumpSettings:
            fetchGlobalPumpSettings()
        case .timeSinceReset:
            fetchTimeSinceReset()
        }
    }
}

extension TandemPumpManager {
    func getActivePumpEvents(endDate: Date? = nil) -> [NewPumpEvent] {
        guard state.basalDose.type == .tempBasal else {
            return []
        }

        let basalEntry = state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
        var events = [
            NewPumpEvent.tempBasal(
                dose: basalEntry,
                date: basalEntry.startDate
            )
        ]

        if endDate != nil, basalEntry.endDate == state.basalDose.estimatedEndDate {
            let dose = UnfinalizedDose(
                basalRate: getScheduledBasalRate(),
                insulinType: state.insulinType,
                startDate: basalEntry.endDate
            )
            events.append(NewPumpEvent.basal(
                dose: dose.toDoseEntry(),
                date: basalEntry.endDate
            ))

            state.basalDose = dose
            notifyDelegateStateUpdated()
        }

        return events
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
        guard let response = bluetooth.write(BolusPermissionReleaseRequest(bolusID: bolusId)) else {
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

    public func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier, completion: @escaping ((any Error)?) -> Void) {
        guard let parsed = NotificationItem.parseStableIdentifier(alertIdentifier) else {
            // Not an identifier this driver minted (e.g. from a newer version) — nothing to
            // relay to the pump, so acknowledge phone-side rather than leave the alert stuck.
            logger.warning("acknowledgeAlert: unrecognized identifier \(alertIdentifier)")
            completion(nil)
            return
        }

        guard let dismissType = parsed.type.dismissType else {
            // Malfunctions cannot be dismissed remotely: acknowledging only silences the
            // phone-side notification. The identifier stays in issuedAlertIdentifiers so the
            // still-active malfunction is not re-issued; it is retracted once the pump
            // reports it cleared.
            logger.info("acknowledgeAlert: \(alertIdentifier) is not dismissible on the pump")
            completion(nil)
            return
        }

        // Prefer the live bundle row for this identifier: a merged row (see
        // `MergedNotificationGroup`) carries the group's primary as its type/notificationId,
        // and `dismissNotification` knows how to acknowledge the merged members the pump
        // does not auto-clear. Both of its paths re-fetch, which runs the alert reconciler.
        if let item = notificationBundle.get().first(where: {
            $0.type == parsed.type && $0.notificationId == parsed.notificationId
        }) {
            dismissNotification(notification: item) { success in
                if success {
                    completion(nil)
                    return
                }

                // The bundle row may be stale: the pump rejects a dismiss for a notification
                // it already cleared itself (e.g. dismissed on the pump between polls), and
                // that must acknowledge cleanly rather than leave the alert stuck. Re-read
                // the pump and only fail the acknowledgement if the notification is really
                // still active (or its state could not be determined).
                self.bluetooth.ensureConnected { error in
                    if let error {
                        completion(error)
                        return
                    }

                    self.fetchNotifications()

                    let bundle = self.notificationBundle
                    let categoryFetched = bundle.fetchedCategories.contains(parsed.type)
                    let stillActive = bundle.isActive(type: parsed.type, id: parsed.notificationId)
                    if categoryFetched, !stillActive {
                        // Already cleared on the pump; the re-fetch's reconcile retracted it.
                        completion(nil)
                    } else {
                        completion(PumpCommError.errorResponse(
                            context: "Failed to dismiss \(alertIdentifier) on the pump"
                        ))
                    }
                }
            }
            return
        }

        // The notification is no longer in the bundle (stale alert or bundle not yet
        // fetched this session) — send a single dismiss for the primary and re-fetch so the
        // reconciler retracts whatever the pump reports as cleared.
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("acknowledgeAlert: failed to connect: \(error.localizedDescription)")
                completion(error)
                return
            }

            // A rejected dismiss here most likely means the pump already cleared the
            // notification itself; don't fail the acknowledgement over it — the re-fetch
            // below retracts the alert if it is really gone.
            if !self.acknowledgeNotification(type: dismissType, id: parsed.notificationId) {
                self.logger.warning("acknowledgeAlert: pump rejected dismiss of stale \(alertIdentifier)")
            }

            self.fetchNotifications()
            completion(nil)
        }
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

/// The resume-with-alarm-acknowledgement sequence used by the settings screen's
/// "Resume Insulin Delivery" button.
///
/// Split out of `TandemPumpManager` so the branching — the ways a resume can end — is unit-testable
/// without a BLE stack; `TandemPumpManager.resumeDeliveryAcknowledgingResumeAlarms` supplies the
/// real pump operations. Like the manager's own command bodies, every operation here is synchronous
/// and must run on the pump command queue with the pump already connected.
struct ResumeWithAlarmAcknowledgement {
    /// Sends one `ResumePumpingRequest`. Returns nil once the pump has resumed, otherwise the error
    /// to report.
    let sendResume: () -> Error?
    /// Re-reads the pump's notification state, so the decision below is made against what the pump
    /// reports now rather than whatever was cached from the last sync.
    let reloadNotifications: () -> Void
    /// The resume-pump alarms active in the notification state last read.
    let activeResumeAlarms: () -> [AlarmStatusResponse.AlarmResponseType]
    /// Acknowledges one alarm. Whether the pump accepts the acknowledgement is deliberately not
    /// consulted — see `run()`.
    let acknowledgeAlarm: (AlarmStatusResponse.AlarmResponseType) -> Void
    /// Progress reporting; the manager passes its logger.
    var log: (String) -> Void = { _ in }

    /// Runs the sequence, returning nil once the pump has resumed or the error to surface.
    func run() -> Error? {
        guard let resumeError = sendResume() else {
            return nil
        }

        reloadNotifications()
        let alarms = activeResumeAlarms()

        // Only the resume-pump alarms are cleared on the user's behalf. A resume that failed for
        // any other reason is reported as-is, so the caller still shows its error.
        guard !alarms.isEmpty else {
            log("Resume failed with no resume-pump alarm active; reporting the failure")
            return resumeError
        }

        let alarmNames = alarms.map { String(describing: $0) }.joined(separator: ", ")
        log("Acknowledging resume-pump alarm(s) [\(alarmNames)] before retrying resume")
        for alarm in alarms {
            acknowledgeAlarm(alarm)
        }

        // Retry regardless of how the acknowledgements were reported: the retry itself is the
        // authority on whether the pump will resume.
        guard let retryError = sendResume() else {
            return nil
        }

        log("Resume retry after acknowledging resume-pump alarm(s) failed")
        // Reload so the notification list and badge reflect the acknowledgements just sent — the
        // caller only re-syncs the pump after a successful resume.
        reloadNotifications()
        return retryError
    }
}

/// Wraps a completion handler so that it is invoked **exactly once**, within a bounded time.
///
/// This is the outermost safety backstop for pump commands (Layer 1). Regardless of what happens
/// in the connection/command layers below it, the caller — e.g. the Trio loop driving a temp basal
/// or bolus — is guaranteed to receive a result and never hang indefinitely. The first of
/// {real completion, timeout} wins; every later invocation is dropped.
///
/// It is intentionally small, pure, and queue-injectable so it can be unit-tested deterministically
/// without touching CoreBluetooth or real wall-clock pacing.
///
/// Note on the timeout value: callers should choose it to be comfortably **larger** than the
/// worst-case real command duration. The command pipeline already self-recovers within its own
/// connect timeout, so the watchdog should essentially never fire in practice; keeping it generous
/// avoids reporting a spurious failure for a command that is legitimately still in progress.
final class CommandWatchdog<Outcome> {
    private let lock = NSLock()
    private var finished = false
    private let onResult: (Outcome) -> Void
    private var timeoutItem: DispatchWorkItem?

    /// - Parameters:
    ///   - timeout: how long to wait before delivering `timeoutResult` if `complete` is not called.
    ///   - timeoutResult: produces the outcome delivered on timeout (evaluated only if it fires).
    ///   - queue: the queue the timeout fires on. It MUST be independent of any queue the wrapped
    ///     work might block, otherwise the timeout could be starved (the bug this whole change fixes).
    ///   - onResult: the wrapped completion; invoked exactly once.
    init(
        timeout: DispatchTimeInterval,
        timeoutResult: @escaping () -> Outcome,
        queue: DispatchQueue,
        onResult: @escaping (Outcome) -> Void
    ) {
        self.onResult = onResult
        let item = DispatchWorkItem { [weak self] in
            self?.deliver(timeoutResult())
        }
        timeoutItem = item
        queue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    /// Delivers `result` if nothing has been delivered yet. Safe to call any number of times and
    /// from any thread; only the first delivery (this call or the timeout) takes effect.
    func complete(_ result: Outcome) {
        deliver(result)
    }

    private func deliver(_ result: Outcome) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let item = timeoutItem
        timeoutItem = nil
        lock.unlock()

        item?.cancel()
        onResult(result)
    }
}

extension TandemPumpManager {
    /// Wraps `completion` with a `CommandWatchdog` and returns a guarded completion. Shadow the
    /// original `completion` at the top of a command method with the result, so every code path
    /// that calls `completion(...)` is single-fire and a wedge below still yields `timeoutResult`.
    func watchdogged<Outcome>(
        timeoutResult: @escaping @autoclosure () -> Outcome,
        timeout: DispatchTimeInterval? = nil,
        _ completion: @escaping (Outcome) -> Void
    ) -> (Outcome) -> Void {
        let watchdog = CommandWatchdog(
            timeout: timeout ?? commandWatchdogTimeout,
            timeoutResult: timeoutResult,
            queue: watchdogQueue,
            onResult: completion
        )
        return { watchdog.complete($0) }
    }
}
