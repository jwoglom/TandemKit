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

    /// Every time-dependent decision below reads `now` rather than the wall clock, so tests can
    /// drive the finalization window, the sync throttle and dose dates without waiting.
    /// Set it before any dose work; nothing re-reads a date it has already stamped.
    var clock: TandemClock

    var now: Date { clock.now }

    func hostDate(forPumpDate date: Date) -> Date {
        let offset = state.pumpClockOffset
        guard TandemPumpManagerState.trustsPumpClockOffset(offset) else { return date }
        return date.addingTimeInterval(-offset)
    }

    // Tandem Mobi and t:slim X2: max 16 basal segments within a profile
    public static var onboardingMaximumBasalScheduleEntryCount: Int = 16

    // Tandem Mobi and t:slim X2: 0.0u, then 0.1 - 15.00u/hr in 0.01u chunks
    public static var onboardingSupportedBasalRates: [Double] = TandemPumpCapabilities.supportedBasalRates

    // Tandem Mobi and t:slim X2: 0.05 - 25.00 unit bolus in 0.05u chunks
    public static var onboardingSupportedBolusVolumes: [Double] = strideRange(from: 0.05, through: 25.0, by: 0.05)

    public static var onboardingSupportedMaximumBolusVolumes: [Double] = strideRange(from: 0.05, through: 25.0, by: 0.01)

    // Tandem Mobi and t:slim X2: a temp rate is a whole percent of the profile basal, 0 - 250%
    internal static let maximumTempBasalPercent: Int = 250
    /// The pump refuses a temp rate outside 15 minutes to 72 hours (pumpX2 `SetTempRateRequest`).
    internal static let supportedTempBasalMinutes = 15 ... 72 * 60

    internal let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    struct PendingPumpEventBatch {
        let events: [NewPumpEvent]
        /// Captured when the batch was emitted, not when it is replayed.
        let lastReconciliation: Date?
        let replacePendingEvents: Bool
    }

    /// `pumpDelegate.notify` hops onto a queue that is `.main` until the host sets one, so the
    /// decision to hold rather than send has to be made synchronously.
    private var pendingPumpEventBatches: [PendingPumpEventBatch] = []
    private let pendingPumpEventLock = NSLock()

    /// Setup sets the pump's clock before the host adopts the manager.
    private var pendingPumpClockAdjustments: [TimeInterval] = []
    private let pendingPumpClockAdjustmentLock = NSLock()

    /// Run once history has reported what `isAwaitingHistory` waits for.
    private var historyWaiters: [() -> Void] = []
    private let historyWaiterLock = NSLock()

    private static let maximumHeldPumpEventBatches = 64

    private var oldState: TandemPumpManagerState
    // Status is published from the command, CoreBluetooth and delegate queues at once; two
    // unserialized swaps of oldState release the same snapshot twice.
    private let publishLock = NSLock()

    // Those queues all read and write state. It holds class references (UnfinalizedDose), so an
    // unserialized write can over-release them; `_modify` keeps `state.x = y` one locked access.
    private let stateLock = NSRecursiveLock()
    private var _state: TandemPumpManagerState
    public var state: TandemPumpManagerState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        _modify {
            stateLock.lock()
            defer {
                recordLogDeviceIdentifier()
                stateLock.unlock()
            }
            yield &_state
        }
        set {
            stateLock.lock()
            defer {
                recordLogDeviceIdentifier()
                stateLock.unlock()
            }
            _state = newValue
        }
    }

    // Every log line reads it, from queues that may hold locks of their own, so it is copied out of
    // state rather than read under stateLock. Written only with stateLock held.
    private var loggedPumpSerial: UInt32?
    private let logDeviceIdentifierLock = NSLock()

    /// The pump's serial number, which the host files `TandemLogger`'s lines under.
    var logDeviceIdentifier: String? {
        logDeviceIdentifierLock.lock()
        defer { logDeviceIdentifierLock.unlock() }
        return loggedPumpSerial.map { String($0) }
    }

    private func recordLogDeviceIdentifier() {
        let serial = _state.pumpState.pumpSerial
        guard serial != loggedPumpSerial else { return }
        logDeviceIdentifierLock.lock()
        loggedPumpSerial = serial
        logDeviceIdentifierLock.unlock()
    }

    internal let logger = TandemLogger(category: "TandemPumpManager")
    internal let telemetryScheduler = PumpTelemetryScheduler(label: "com.loopkit.TandemKit.TelemetryScheduler")

    // Status tracking
    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()

    // Stream message publishers
    public let fillTubingStateStream = PassthroughSubject<FillTubingStateStreamResponse, Never>()
    public let fillCannulaStateStream = PassthroughSubject<FillCannulaStateStreamResponse, Never>()
    public let changeCartridgeStateStream = PassthroughSubject<EnterChangeCartridgeModeStateStreamResponse, Never>()
    public let detectingCartridgeStateStream = PassthroughSubject<DetectingCartridgeStateStreamResponse, Never>()
    public let exitFillTubingModeStateStream = PassthroughSubject<ExitFillTubingModeStateStreamResponse, Never>()
    public let pumpingStateStream = PassthroughSubject<PumpingStateStreamResponse, Never>()
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

    /// Held for the duration of any history read, so the log viewer and the background backfill
    /// can't consume each other's entries off the shared `historyLogStream`.
    let historyFetchGate = HistoryFetchGate()

    /// Keeps the session store caught up with the pump's log, a slice at a time. Driven from
    /// `syncPumpData` rather than `telemetryScheduler`, which the bolus path cancels wholesale.
    lazy var historyBackfillCoordinator = HistoryBackfillCoordinator(pumpManager: self)

    // Set on the command queue, read on the telemetry queue and the host's.
    private let bolusProgressReportLock = NSLock()
    private var _bolusProgressReport: TandemDoseProgressReporter?
    internal var bolusProgressReport: TandemDoseProgressReporter? {
        get {
            bolusProgressReportLock.lock()
            defer { bolusProgressReportLock.unlock() }
            return _bolusProgressReport
        }
        set {
            bolusProgressReportLock.lock()
            _bolusProgressReport = newValue
            bolusProgressReportLock.unlock()
        }
    }
    private let silentToneManager = TandemSilentToneManager()
    var notificationBundle = NotificationBundle()
    var unreportedInsulinOnBoard = UnreportedInsulinOnBoardMonitor()

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
    /// How long a sync that saw a delivery change waits for history to date it.
    var transitionHistoryWait: DispatchTimeInterval = .seconds(30)

    // Syncs queued or running on the command queue. Loop polls every ~5 minutes, and a sync
    // against an unresponsive pump spends that long working through bounded write timeouts, so
    // the polls have to be told to stand down rather than stack up behind it — as would every
    // user command sharing that queue. Guarded because syncs start and finish on different queues.
    private let syncStateLock = NSLock()
    private var inFlightSyncs = 0
    // A poll that stands down takes this sync's result: Trio loops on whatever it is handed, and
    // the in-flight sync may be the one after a reconnect, the first to read the pump since an outage.
    private var latestSyncResult: SyncResult?

    /// The temp `maintainPumpClockSkewCompensation` has running. Only touched from command queue jobs.
    var skewCompensationTemp: (percent: Int, endsAt: Date)?

    /// The BasalDelivery records whose basal difference has been logged this session. Only touched
    /// from command queue jobs.
    var loggedBasalDifferences = Set<UInt32>()
    /// The records whose basal history check failure has been logged this session. Command queue only.
    var loggedBasalProblems = Set<UInt32>()
    /// Command queue only.
    var basalResidualDays = BasalReconciler.ResidualDays()
    /// How many history passes each store gap has held basal reconciliation back. Command queue only.
    var basalGapPasses: [ClosedRange<UInt32>: Int] = [:]
    /// Written by history passes on the command queue and read by the Reconciliation debug screen.
    private let reconciliationLogLock = NSLock()
    private var _reconciliationLog = ReconciliationLog()
    var reconciliationLog: ReconciliationLog {
        get {
            reconciliationLogLock.lock()
            defer { reconciliationLogLock.unlock() }
            return _reconciliationLog
        }
        _modify {
            reconciliationLogLock.lock()
            defer { reconciliationLogLock.unlock() }
            yield &_reconciliationLog
        }
        set {
            reconciliationLogLock.lock()
            defer { reconciliationLogLock.unlock() }
            _reconciliationLog = newValue
        }
    }
    /// Paces `updatePumpBasalProfile`: one write in flight, the next no sooner than
    /// `basalProfileUpdateRetryInterval`, however many basal readings arrive meanwhile.
    let basalProfileUpdateLock = NSLock()
    var basalProfileUpdateInFlight = false
    var lastBasalProfileUpdateAttempt: Date?

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

    /// `pumpDelegate.queue` reads back as `.main` until the host sets one, and the host asserts its
    /// delegate methods run on its own queue, so this cannot be inferred from the holder.
    private var hasDelegateQueue = false

    private static func makeStatus(from state: TandemPumpManagerState) -> PumpManagerStatus {
        PumpManagerStatus(
            timeZone: TimeZone.current,
            device: state.deviceInfo,
            pumpBatteryChargeRemaining: state.lastBatteryReading?.chargeRemaining,
            basalDeliveryState: state.basalDeliveryState,
            bolusState: state.bolusState,
            insulinType: state.insulinType,
            deliveryIsUncertain: state.bolusDose?.isUnconfirmed == true
        )
    }

    public convenience init(state: TandemPumpManagerState) {
        self.init(state: state, bluetooth: TandemBluetoothManager())
    }

    /// Designated initializer. Tests inject a stub `bluetooth` here to drive command sequences
    /// without CoreBluetooth; production goes through `init(state:)`.
    init(state: TandemPumpManagerState, bluetooth: PumpBluetoothConnection, clock: TandemClock = SystemClock()) {
        _state = state
        loggedPumpSerial = state.pumpState.pumpSerial
        oldState = TandemPumpManagerState(rawValue: state.rawValue)
        self.bluetooth = bluetooth
        self.clock = clock
        bluetooth.pumpManager = self
        logInitialization()
        #if TANDEMKIT_VIRTUAL_PUMP
        VirtualPumpControl.attach(self)
        #endif

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

    private func logInitialization() {
        let app = Bundle.main.bundleIdentifier ?? "unknown"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String
        logger.info("TandemKit initialized, commit \(Self.gitCommit) running in \(app) version \(version)\(build.map { " (\($0))" } ?? "")")
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
        ["## TandemPumpManager", "* gitCommit: \(Self.gitCommit)", state.debugDescription].joined(separator: "\n")
    }

    private static var gitCommit: String {
        Bundle(for: TandemPumpManager.self).object(forInfoDictionaryKey: "TandemKitGitCommit") as? String ?? "unknown"
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
        TandemPumpCapabilities.floor(units, ontoGrid: supportedBolusVolumes)
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        TandemPumpCapabilities.floor(unitsPerHour, ontoGrid: supportedBasalRates)
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
        notifyDelegate(includingState: true)
    }

    private func notifyDelegate(includingState: Bool) {
        publishLock.lock()
        let current = state
        let status = TandemPumpManager.makeStatus(from: current)
        let oldStatus = TandemPumpManager.makeStatus(from: oldState)
        oldState = TandemPumpManagerState(rawValue: current.rawValue)
        publishLock.unlock()

        // Until the host sets its queue this would land on `.main`; attaching sends the status then.
        if canNotifyDelegate, let delegate = pumpManagerDelegate {
            pumpDelegate.queue.async { [weak self] in
                guard let self = self else { return }

                if includingState {
                    delegate.pumpManagerDidUpdateState(self)
                }
                delegate.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }
        }

        statusObservers.forEach { observer in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
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

    /// The percent the pump is told to run and the rate that percent delivers, resolved together
    /// so the value sent to the pump and the value reported to the host cannot disagree.
    ///
    /// A temp basal is a whole percent of the profile basal, so rounding to the nearest one can
    /// deliver up to `baseline * 0.5%` more than was asked for. Trio drops any temp-basal record
    /// whose `unitsPerHour` exceeds its `maxBasal` and oref routinely requests exactly `maxBasal`,
    /// so the percent is stepped down until the rate no longer exceeds the request.
    ///
    /// The pump refuses a percent whose share of the profile is under its lowest rate (status 1):
    /// 17% of 0.58 U/hr is 0.0986 U/hr, and oref asks for the 0.1 U/hr it is short of whenever a
    /// zero temp is a little less than needed. The lowest percent the pump accepts goes out
    /// instead, the nearer of the two it does accept either side of the request: it overshoots by
    /// under a percent of the baseline, where 0% falls the whole request short. A request under the
    /// lowest rate itself is 0%, as `roundToSupportedBasalRate` makes it before this is called.
    internal func tempBasalPercentAndRate(requestedRate: Double, baseline: Double) -> (percent: Int, rate: Double) {
        guard baseline > 0, requestedRate > 0 else { return (0, 0) }

        let ideal = requestedRate / baseline * 100.0
        var percent = max(0, min(Int(ideal.rounded()), TandemPumpManager.maximumTempBasalPercent))
        var rate = roundToSupportedBasalRate(unitsPerHour: baseline * Double(percent) / 100.0)

        // One step is enough from a nearest-rounded percent, but loop rather than assume it: the
        // grid, the ceiling and the rounding mode are all free to change independently. Terminates
        // because 0% delivers 0 U/h and `requestedRate` is positive.
        while percent > 0, rate > requestedRate {
            percent -= 1
            rate = roundToSupportedBasalRate(unitsPerHour: baseline * Double(percent) / 100.0)
        }

        let lowestAccepted = min(Self.minimumTempBasalPercent(baseline: baseline), TandemPumpManager.maximumTempBasalPercent)
        if percent > 0, percent < lowestAccepted {
            let raised = requestedRate >= TandemPumpCapabilities.minimumBasalRate ? lowestAccepted : 0
            logger.info(
                "Sending a \(raised)% temp basal: \(percent)% of \(baseline) U/hr is under the pump's \(TandemPumpCapabilities.minimumBasalRate) U/hr minimum"
            )
            percent = raised
            rate = roundToSupportedBasalRate(unitsPerHour: baseline * Double(percent) / 100.0)
        }

        return (percent, rate)
    }

    /// The lowest non-zero percent the pump accepts of `baseline`: the first whose share of it, in
    /// the milliunits the pump holds the profile in, reaches `TandemPumpCapabilities.minimumBasalRate`.
    /// Whether the pump compares that share exactly or truncated to a milliunit, one of at least
    /// 100 mU passes either test.
    internal static func minimumTempBasalPercent(baseline: Double) -> Int {
        let baselineMilliunits = Int((baseline * 1000).rounded())
        guard baselineMilliunits > 0 else { return 1 }
        let minimumMilliunits = Int((TandemPumpCapabilities.minimumBasalRate * 1000).rounded())
        return (minimumMilliunits * 100 + baselineMilliunits - 1) / baselineMilliunits
    }

    internal static func tempBasalExceedsCeiling(requestedRate: Double, baseline: Double) -> Bool {
        guard baseline > 0, requestedRate > 0 else { return false }
        return Int((requestedRate / baseline * 100.0).rounded()) > maximumTempBasalPercent
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

    /// Catches the host up on what only gets pushed once, since the manager reads the pump before
    /// the host adopts it. Called from both setters — the host sets them one after the other (Trio
    /// sets the delegate first) and `notify` needs both — so whichever lands second does the work.
    private func deliverStateMissedByTheDelegate() {
        guard pumpDelegate.delegate != nil, hasDelegateQueue else { return }

        TandemLogger.pumpManager = self
        bluetooth.pumpManagerWasAdopted()
        // Not pumpManagerDidUpdateState: Loop and Trio save rawValue on the main thread right after
        // attaching, and its save from their delegate queue races that one.
        notifyDelegate(includingState: false)
        flushPendingPumpEvents()
        flushPendingReservoirReading()
        flushPendingPumpClockAdjustments()
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

        // Not while the link is down: this sync is the host's one periodic chance to reconnect.
        // Nor while a bolus is unconfirmed, which only a read of the pump settles.
        if let lastSync = state.lastReconciliation, now.timeIntervalSince(lastSync) < .minutes(4.5),
           !isAwaitingHistory, state.isConnected, state.bolusDose?.isUnconfirmed != true
        {
            logger.warning("State already in sync: \(now.timeIntervalSince(lastSync)) sec")
            completion?(lastSync)
            return
        }

        syncPumpData(onlyIfIdle: true, completion: completion)
    }

    /// Registers a sync as in flight and returns where its result goes. Nil only when `onlyIfIdle`
    /// and one already is, in which case `completion` is handed that sync's result.
    private func beginSync(onlyIfIdle: Bool, completion: ((_ lastSync: Date?) -> Void)?) -> SyncResult? {
        syncStateLock.lock()
        if onlyIfIdle, inFlightSyncs > 0, let running = latestSyncResult {
            syncStateLock.unlock()
            running.whenSet { completion?($0) }
            return nil
        }
        inFlightSyncs += 1
        let result = SyncResult()
        latestSyncResult = result
        syncStateLock.unlock()
        return result
    }

    private func endSync() {
        syncStateLock.lock()
        inFlightSyncs -= 1
        syncStateLock.unlock()
    }

    /// - Parameter onlyIfIdle: when a sync is already queued or running, queue nothing and complete
    ///   with its result. Set by the automatic poll; a sync the user asked for runs regardless.
    func syncPumpData(onlyIfIdle: Bool = false, completion: ((_ lastSync: Date?) -> Void)?) {
        guard let result = beginSync(onlyIfIdle: onlyIfIdle, completion: completion) else {
            logger.warning("A sync is already in flight; waiting for its result instead of queueing another")
            return
        }

        // Layer 1 backstop: always hand the loop a lastSync, even if the layers below wedge.
        // Capture lastReconciliation in a local so the timeoutResult autoclosure doesn't reference
        // `self` — `self.state` here gets stripped by the Swiftformat build phase (redundantSelf),
        // which then fails to compile because the autoclosure escapes.
        let lastReconciliation = state.lastReconciliation
        let completion = watchdogged(timeoutResult: lastReconciliation) { lastSync in
            completion?(lastSync)
            result.set(lastSync)
        }
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
            if lastSettingsCheckedAt == nil || self.now.timeIntervalSince(lastSettingsCheckedAt!) > .hours(24) {
                self.fetchControlIQStatus()
                self.fetchDeliveryLimits()
                self.fetchGlobalPumpSettings()
                self.fetchPumpInformation()
                self.fetchInsulinDuration()

                // Same reason as lastSync below: stamping this after a pump that answered nothing
                // would suppress the next attempt for 24 hours.
                if self.bluetooth.responseCount > responsesBefore {
                    self.state.lastSettingsCheckedAt = self.now
                }
            } else if !self.state.featureFlags.quickBolusButtonSupport {
                // The quick bolus button is confirmed off every cycle, which needs a fresh read.
                self.fetchGlobalPumpSettings()
            }

            if self.state.pumpInsulinDuration == nil {
                self.fetchInsulinDuration()
            }
            self.enforceQuickBolusDisabled()

            // Ahead of the basal read, which looks segments up on the pump's clock.
            self.fetchTimeSinceReset()
            self.fetchReservoirStatus()
            self.fetchBatteryStatus()
            let readBolusState = self.fetchBolusStatus(fromSync: true)
            self.finalizePendingBolus()
            let readBasalState = self.fetchBasalStatus()
            self.fetchInsulinOnBoard()
            self.fetchNotifications()
            self.fetchCGMSessionStatus()

            // Not on any answer: a pump that answered the rest of the sync has still said nothing
            // about delivery, and advancing lastSync promises the host a reconciliation that never happened.
            if readBolusState, readBasalState {
                self.state.lastReconciliation = self.now
                self.reportPendingDoses()
                self.flushPendingReservoirReading()
            } else {
                self.logger.error("Sync got no answer to its bolus or basal status read; leaving lastSync where it was")
            }

            self.notifyDelegateStateUpdated()

            // Kicked off, not awaited: a backfill slice can take far longer than a sync cycle,
            // and the loop is waiting on `completion` for the status reads above, not on
            // history. Overlapping ticks are dropped by the coordinator.
            guard self.isAwaitingHistory || self.awaitsHistoryBoluses else {
                self.historyBackfillCoordinator.runTick()
                completion(self.state.lastReconciliation)
                return
            }

            // Except when the reads saw a change history has to date, Control-IQ has handed back,
            // or the pump may have bolused on its own: the host doses on this result, and needs
            // what the pump did first.
            self.afterHistoryIsReported {
                completion(self.state.lastReconciliation)
            }
            self.historyBackfillCoordinator.runTick()
        }
    }

    /// Runs `completion` once a history pass has reported what `isAwaitingHistory` waits for, or
    /// after `transitionHistoryWait`, a pending delivery change then reported at detection.
    func afterHistoryIsReported(_ completion: @escaping () -> Void) {
        let finish = watchdogged(timeoutResult: false, timeout: transitionHistoryWait) { reported in
            guard !reported else {
                completion()
                return
            }
            self.bluetooth.ensureConnected { _ in
                self.settleDeliveryTransition()
                completion()
            }
        }
        historyWaiterLock.lock()
        historyWaiters.append { finish(true) }
        historyWaiterLock.unlock()
    }

    func releaseHistoryWaiters() {
        historyWaiterLock.lock()
        let waiters = historyWaiters
        historyWaiters = []
        historyWaiterLock.unlock()
        waiters.forEach { $0() }
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

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        bolusProgressReport?.reporting(on: dispatchQueue)
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        TandemPumpCapabilities.estimatedBolusDuration(toDeliver: units)
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

        if let maxBolus = state.settings.maxBolus,
           TandemPumpCapabilities.milliunits(units) > TandemPumpCapabilities.milliunits(maxBolus)
        {
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

        if state.isPumpClockUntrusted {
            logger.warning("[enactBolus] Blocked: the pump's clock is \(Int(state.pumpClockOffset)) s off the phone's")
            completion(.deviceState(TandemPumpManagerValidationError.pumpClockUntrusted))
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

        if shouldDeferBolusSync() {
            refuseWhileABolusRuns(.enactBolus, completion)
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for bolus: \(error.localizedDescription)")
                completion(.communication(PumpCommError.pumpNotConnected))
                return
            }

            // Again here: a second enact queues behind the first's job and runs right after its InitiateBolus.
            guard !self.bolusIsStillRunning() else {
                self.refuseWhileABolusRuns(.enactBolus, completion)
                return
            }

            let permissionRequest = BolusPermissionRequest()
            guard let permissionResponse = self.bluetooth.write(permissionRequest) else {
                self.logger.error("Failed to request bolus permission")
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard permissionResponse.isPermissionGranted else {
                self.logger.error("Pump rejected bolus permission request: \(permissionResponse.description)")
                completion(.deviceState(PumpRefusal.bolusPermission(permissionResponse, to: permissionRequest)))
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
            let sentAt = self.now
            guard let initiateResponse = self.bluetooth.write(bolusRequest) else {
                completion(self.settleUnansweredBolus(
                    units: units,
                    activationType: activationType,
                    bolusId: permissionResponse.bolusId,
                    sentAt: sentAt
                ))
                return
            }

            guard initiateResponse.wasBolusInitiated else {
                self.logger.error("Bolus was not initiated: \(initiateResponse.description)")
                self.releaseBolusPermission(bolusId: permissionResponse.bolusId)
                completion(.deviceState(PumpRefusal.initiateBolus(initiateResponse, to: bolusRequest)))
                return
            }

            self.registerCommandedBolus(
                units: units,
                activationType: activationType,
                bolusId: permissionResponse.bolusId,
                startDate: sentAt,
                isUnconfirmed: false
            )
            completion(nil)
        }
    }

    /// An `InitiateBolus` whose answer was lost may still have started the bolus, and a write gives
    /// nil whether the request never left the phone, the pump refused it or its answer was lost.
    private func settleUnansweredBolus(
        units: Double,
        activationType: BolusActivationType,
        bolusId: Int,
        sentAt: Date
    ) -> PumpManagerError? {
        let finding = bluetooth.write(CurrentBolusStatusRequest()).map { findUnansweredBolus(bolusId, status: $0) } ?? .unanswered
        switch finding {
        case .started:
            logger.warning("No answer to InitiateBolus, but the pump took bolus \(bolusId); reporting it")
            registerCommandedBolus(units: units, activationType: activationType, bolusId: bolusId, startDate: sentAt, isUnconfirmed: false)
            return nil
        case .notStarted:
            logger.error("No answer to InitiateBolus, and the pump did not start bolus \(bolusId)")
            releaseBolusPermission(bolusId: bolusId)
            return .communication(PumpCommError.noResponse)
        case .unanswered, .hiddenByLaterBolus:
            logger.error("No answer to InitiateBolus, and the pump can't say whether it started bolus \(bolusId); reporting it as delivering")
            registerCommandedBolus(units: units, activationType: activationType, bolusId: bolusId, startDate: sentAt, isUnconfirmed: true)
            return .uncertainDelivery
        }
    }

    /// Reported mutable at its programmed amount from the moment the pump may have it, so neither
    /// host can dose without counting it.
    private func registerCommandedBolus(
        units: Double,
        activationType: BolusActivationType,
        bolusId: Int,
        startDate: Date,
        isUnconfirmed: Bool
    ) {
        let dose = UnfinalizedDose(
            units: units,
            // The pump spends ~15s accepting the request before insulin moves.
            duration: estimatedDuration(toBolus: units) + TandemPumpCapabilities.bolusInitiationDelay,
            activationType: activationType,
            insulinType: state.insulinType,
            bolusId: bolusId,
            now: startDate
        )
        dose.isUnconfirmed = isUnconfirmed
        dose.eventRaw = bolusEventRaw(bolusId: bolusId)

        let doseEntry = dose.toDoseEntry(isMutable: true)
        // An unconfirmed bolus gets one once the pump is seen delivering it.
        if !isUnconfirmed {
            bolusProgressReport = TandemDoseProgressReporter(
                pumpManager: self,
                dose: doseEntry,
                activationType: activationType,
                eventRaw: dose.eventRaw
            )
        }

        let event = NewPumpEvent.bolus(dose: doseEntry, of: dose)
        state.bolusReportLedger.prune(now: now)
        state.bolusReportLedger.record(BolusReportLedger.Entry(
            bolusId: bolusId,
            pumpSerial: HistoryLogSyncIdentifier.PumpSerial(state.pumpState.pumpSerial)?.rawValue,
            origin: .commanded,
            raw: event.raw,
            eventDate: event.date,
            automatic: activationType.isAutomatic,
            isFinalized: false,
            units: doseEntry.programmedUnits
        ))

        state.bolusDose = dose
        state.bolusState = .initiating
        state.lastReconciliation = now
        notifyDelegateStateUpdated()
        emitPumpEvents([event], replacePendingEvents: false)
    }

    private var isBolusInFlight: Bool {
        state.bolusDose != nil || state.bolusState != .noBolus || bolusProgressReport?.isUnfinalized() == true
    }

    /// Past its estimated end a bolus may have finished out of contact, or may still be running on a
    /// pump slower than the estimate, so the pump is asked.
    private func bolusIsStillRunning() -> Bool {
        if isBolusInFlight, !shouldDeferBolusSync() {
            fetchBolusStatus(fromSync: true)
        }
        return isBolusInFlight
    }

    private enum DosingCommand: String {
        case enactBolus
        case enactTempBasal
    }

    private func refuseWhileABolusRuns(_ command: DosingCommand, _ completion: (PumpManagerError?) -> Void) {
        logger.warning("[\(command.rawValue)] Blocked: bolus \(state.bolusDose?.bolusId ?? -1) is still running")
        completion(.deviceState(TandemPumpManagerValidationError.bolusIsRunning))
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

            let cancelRequest = CancelBolusRequest(bolusId: bolusId)
            guard let response = self.bluetooth.write(cancelRequest) else {
                self.logger.error("Failed to cancel bolus")
                completion(.failure(.communication(PumpCommError.noResponse)))
                return
            }

            guard response.wasCancelled else {
                self.logger.error("Pump failed to cancel bolus: \(response.description)")
                completion(.failure(.deviceState(PumpRefusal.cancelBolus(response, to: cancelRequest))))
                return
            }
            let stoppedAt = self.now

            // Allow the Mobi to store the bolus in storage
            Thread.sleep(forTimeInterval: .seconds(2))

            // From programming when delivery start was never seen: over by the initiation delay,
            // never under. Not the progress reporter's estimate, which is 0 U until a second
            // delivering status (#448).
            let estimatedDelivered = TandemPumpCapabilities.roundToReportingResolution(TandemPumpCapabilities.unitsDelivered(
                in: stoppedAt.timeIntervalSince(bolusDose.deliveryStartDate ?? bolusDose.startDate),
                ofBolus: bolusDose.value
            ))

            self.telemetryScheduler.cancelAll()
            self.bolusProgressReport = nil
            self.state.bolusDose = nil
            self.state.bolusState = .noBolus

            guard let lastBolus = self.queryLastBolusReport(bolusId: bolusId) else {
                // Unknown, not zero: finalizing at 0 would permanently erase the insulin that
                // went in before the cancel (#328).
                self.logger.error(
                    "No delivered volume for cancelled bolus \(bolusId); keeping it mutable and retrying on the next sync"
                )
                self.holdForFinalization(bolusDose, fallbackUnits: estimatedDelivered)

                let mutableDose = bolusDose.toDoseEntry(isMutable: true)
                var events = self.getActivePumpEvents()
                events.append(NewPumpEvent.bolus(dose: mutableDose, of: bolusDose))

                self.state.lastReconciliation = self.now
                self.notifyDelegateStateUpdated()
                self.emitPumpEvents(events)

                completion(.success(mutableDose))
                return
            }

            bolusDose.deliveredUnits = lastBolus.deliveredUnits

            // Not now: a cancel is only noticed here, while the insulin stopped going in when the
            // pump says it did (#339).
            let canceledDose = bolusDose.toDoseEntry(endDate: BolusEndDate.resolve(
                startDate: bolusDose.startDate,
                deliveryStartDate: bolusDose.deliveryStartDate,
                deliveredUnits: bolusDose.deliveredUnits,
                pumpTimestamp: self.hostDate(forPumpDate: lastBolus.pumpTimestamp),
                detectedAt: stoppedAt
            ))

            var events = self.getActivePumpEvents()
            // A zero delivery is finalized at 0 U, not withdrawn: Loop purges nothing on an empty batch,
            // and keeps a 0 U bolus out of IOB and HealthKit itself.
            events.append(NewPumpEvent.bolus(dose: canceledDose, of: bolusDose))

            self.state.lastReconciliation = self.now
            self.notifyDelegateStateUpdated()
            self.emitPumpEvents(events)

            completion(.success(canceledDose))
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

        if shouldDeferBolusSync() {
            refuseWhileABolusRuns(.enactTempBasal, completion)
            return
        }

        let isCancel = duration <= 0
        // 0% of any profile is 0, so a zero temp is safe whatever the pump holds, and always allowed.
        let isZeroTemp = !isCancel && unitsPerHour == 0

        guard isCancel || isZeroTemp || !state.isPumpClockUntrusted else {
            logger.warning("[enactTempBasal] Blocked: the pump's clock is \(Int(state.pumpClockOffset)) s off the phone's")
            completion(.deviceState(TandemPumpManagerValidationError.pumpClockUntrusted))
            return
        }

        // Refused before anything is sent: the pump would refuse it after the running temp was stopped.
        let minutes = Int(exactly: duration.minutes.rounded(.down)) ?? Int.max
        guard isCancel || Self.supportedTempBasalMinutes.contains(minutes) else {
            logger.error("[enactTempBasal] Blocked: the pump does not accept a temp basal of \(duration.minutes) min")
            completion(.configuration(TandemPumpManagerValidationError.unsupportedTempBasalDuration(minutes: minutes)))
            return
        }
        // The pump takes whole minutes, so the temp is reported for what it was sent.
        let programmedDuration = TimeInterval.minutes(Double(minutes))

        guard isZeroTemp || getScheduledBasalRate() > 0 else {
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

            guard !self.bolusIsStillRunning() else {
                self.refuseWhileABolusRuns(.enactTempBasal, completion)
                return
            }

            // A cancel still goes through: it returns the pump to its own profile, whatever that holds.
            if !isCancel, !isZeroTemp {
                self.adoptMatchingPumpProfile()
                guard !self.state.basalProfileUpdateFailed else {
                    self.logger.warning("[enactTempBasal] Blocked: the pump's basal profile could not be updated to match the schedule")
                    completion(.configuration(TandemPumpManagerValidationError.failedUpdatePumpProfile))
                    return
                }
                guard self.state.hasSyncedBasalRateSchedule else {
                    self.logger.warning("[enactTempBasal] Blocked: the basal schedule has never been synced to the pump")
                    completion(.configuration(TandemPumpManagerValidationError.basalScheduleNotSynced))
                    return
                }
            }

            guard let currentBasal = self.bluetooth.write(CurrentBasalStatusRequest()) else {
                self.logger.error("Failed to fetch current temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }
            self.observeDeliveryState(currentBasal.basalType)

            if !isCancel, !isZeroTemp, currentBasal.profileBasalRate == 0 {
                self.logger.error("[enactTempBasal] Blocked: the pump's profile basal rate is 0 U/hr")
                completion(.deviceState(TandemPumpManagerValidationError.pumpProfileBasalRateIsZero))
                return
            }

            // Everything the pump could refuse is settled before the running temp is stopped: a
            // refusal after the stop leaves the pump on its profile until the next cycle.
            let baseline = self.tempBasalBaseline(pumpRate: currentBasal.profileBasalRate)
            let requestedRate = isCancel ? 0 : self.clampedToPumpMaximumBasalRate(unitsPerHour)
            let (percent, absoluteRate) = isCancel ? (100, 0) : self.tempBasalPercentAndRate(
                requestedRate: requestedRate,
                baseline: baseline
            )

            if !isCancel, Self.tempBasalExceedsCeiling(requestedRate: requestedRate, baseline: baseline) {
                self.logger.warning(
                    "Clamped temp basal \(requestedRate) → \(absoluteRate) U/hr (\(percent)% of \(baseline) U/hr profile)"
                )
            }

            let tempWasRunning = currentBasal.basalType == .tempBasal
            let stoppedTemp = tempWasRunning && self.state.basalDose.type == .tempBasal ? self.state.basalDose : nil
            if tempWasRunning {
                let stopRequest = StopTempRateRequest()
                guard let stopCurrentRate = self.bluetooth.write(stopRequest) else {
                    self.logger.error("Failed to stop temp rate")
                    completion(.communication(PumpCommError.noResponse))
                    return
                }

                guard stopCurrentRate.isStatusOK else {
                    self.logger.error("Failed to stop temp rate - Status: \(stopCurrentRate.status)")
                    completion(.deviceState(PumpRefusal.stopTempBasal(stopCurrentRate, to: stopRequest, replacing: !isCancel)))
                    return
                }

                self.logger.info("Current temp basal cancelled!")
                self.skewCompensationTemp = nil
            }

            // Skewed, the host counts its own schedule rather than the pump's rate when no temp runs.
            let hostCountsThePumpsRate = !self.state.isPumpClockSkewed
                || TandemPumpCapabilities.milliunits(absoluteRate) == TandemPumpCapabilities.milliunits(self.getScheduledBasalRate())
            if percent == 100, isCancel || hostCountsThePumpsRate {
                self.logger.info("Enact completed! (no basal rate change)")
                self.startScheduledBasalDose(reading: currentBasal)
                if self.state.isPumpClockSkewed, let status = self.bluetooth.write(CurrentBasalStatusRequest()) {
                    self.maintainPumpClockSkewCompensation(status)
                }
                completion(nil)
                return
            }

            let request = SetTempRateRequest(minutes: minutes, percent: percent)
            guard let response = self.bluetooth.write(request) else {
                self.logger.error("Failed to set temp rate")
                let outcome = self.adoptUnansweredTempBasal(rate: absoluteRate, percent: percent, duration: programmedDuration)
                if !outcome.adopted, outcome.status?.basalType == .basal {
                    self.restoreStoppedTempBasal(stoppedTemp)
                }
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard response.isStatusOK else {
                self.logger
                    .error(
                        "Failed to set temp rate - Status: \(response.status), percent: \(percent), duration: \(minutes)min"
                    )
                self.restoreStoppedTempBasal(stoppedTemp)
                completion(.deviceState(PumpRefusal.tempBasal(
                    response,
                    to: request,
                    pumpBasalRate: currentBasal.profileBasalRate,
                    maximumTempBasalRate: self.state.settings.maxTempBasalRate,
                    afterStoppingATemp: tempWasRunning
                )))
                return
            }

            if let readback = self.bluetooth.write(CurrentBasalStatusRequest()) {
                guard Self.tempBasalReadbackMatches(readback, percent: percent) else {
                    self.rejectMismatchedTempBasal(
                        readback,
                        expectedRate: absoluteRate,
                        percent: percent,
                        duration: programmedDuration,
                        tempRateId: response.tempRateId,
                        completion: completion
                    )
                    return
                }
            } else {
                self.logger.warning("No basal status after setting the temp basal; reporting it as commanded")
            }

            self.recordTempBasal(rate: absoluteRate, percent: percent, duration: programmedDuration, tempRateId: response.tempRateId)
            self.logger.info("Temp basal enacted!")
            completion(nil)
        }
    }

    /// A `SetTempRate` whose answer was lost may still have reached the pump, after the stop of the
    /// temp it replaces did.
    private func adoptUnansweredTempBasal(
        rate: Double,
        percent: Int,
        duration: TimeInterval
    ) -> (status: CurrentBasalStatusResponse?, adopted: Bool) {
        guard let status = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.warning("No basal status after an unanswered SetTempRate; the next reading settles it")
            return (nil, false)
        }
        guard Self.tempBasalReadbackMatches(status, percent: percent),
              let temp = bluetooth.write(TempRateRequest()), temp.active, temp.percentage == percent
        else {
            observeDeliveryState(status.basalType)
            return (status, false)
        }
        logger.warning("The pump runs the \(percent)% temp basal whose SetTempRate answer was lost; reporting it")
        recordTempBasal(rate: rate, percent: percent, duration: duration, tempRateId: nil)
        return (status, true)
    }

    /// The temp a refused replacement was stopped for is set again for what remained of it, so the
    /// pump runs its profile only when that fails too. The host counts the temp it was told of, and
    /// a profile above it over-delivers until the next cycle; a zero temp most of all.
    private func restoreStoppedTempBasal(_ stopped: UnfinalizedDose?) {
        guard let stopped, let percent = stopped.tempPercent else { return }
        let minutes = Int(stopped.estimatedEndDate.timeIntervalSince(now).minutes.rounded(.down))
        guard Self.supportedTempBasalMinutes.contains(minutes) else {
            logger.warning("Not restoring the stopped \(percent)% temp basal with \(minutes) min left; the pump runs its profile")
            return
        }
        guard let response = bluetooth.write(SetTempRateRequest(minutes: minutes, percent: percent)), response.isStatusOK else {
            logger.error("Could not restore the stopped \(percent)% temp basal; the pump runs its profile")
            return
        }
        logger.warning("Restored the stopped \(percent)% temp basal for the \(minutes) min left of it")
        recordTempBasal(rate: stopped.value, percent: percent, duration: .minutes(Double(minutes)), tempRateId: response.tempRateId)
    }

    /// The pump refuses a temp above its max basal rate limit, so a request above it is made the
    /// limit, the most the pump will run, rather than refused after the running temp was stopped.
    /// The limit read from the pump is what it enforces; the one the host synced stands in until
    /// the daily settings read.
    func clampedToPumpMaximumBasalRate(_ unitsPerHour: Double) -> Double {
        let limit: Double? = if let milliunits = state.maxBasalLimitMilliunits, milliunits > 0 {
            Double(milliunits) / 1000
        } else {
            state.settings.maxTempBasalRate
        }
        guard let limit, TandemPumpCapabilities.milliunits(unitsPerHour) > TandemPumpCapabilities.milliunits(limit) else {
            return unitsPerHour
        }
        logger.warning("Clamped temp basal \(unitsPerHour) → \(limit) U/hr, the pump's maximum basal rate limit")
        return limit
    }

    private func recordTempBasal(rate: Double, percent: Int, duration: TimeInterval, tempRateId: Int?) {
        settleDeliveryTransition()
        let dose = UnfinalizedDose(
            tempRate: rate,
            duration: duration,
            automatic: true,
            insulinType: state.insulinType,
            startDate: now,
            tempRateId: tempRateId,
            tempPercent: percent,
            eventRaw: tempBasalEventRaw(tempRateId: tempRateId)
        )
        var events = getActivePumpEvents(endDate: dose.startDate)
        events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true), of: dose))

        state.deliveryTransitions.interruptedTemp = nil
        state.basalDose = dose
        state.lastReconciliation = dose.startDate

        notifyDelegateStateUpdated()
        emitPumpEvents(events)
    }

    /// Nil without the serial, or for an id not past the last minted: the pump's 16-bit counter may
    /// restart, and a host still holding a row under an id's earlier use would swallow the new temp.
    func tempBasalEventRaw(tempRateId: Int?) -> Data? {
        guard let tempRateId, tempRateId > 0, let serial = historyLogStoreSerial else {
            return nil
        }
        if let last = state.lastTempRateEventRaw.flatMap(HistoryLogSyncIdentifier.decode), last.pumpSerial == serial,
           tempRateId <= last.identifier
        {
            logger.warning("Temp rate id \(tempRateId) is not past \(last.identifier); keying the temp basal on what was programmed")
            return nil
        }
        let raw = HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId)
        state.lastTempRateEventRaw = raw
        return raw
    }

    /// As `tempBasalEventRaw`, from the pump's `bolusId`. History reports the bolus under the same
    /// `raw`, so a later pump manager's history load finds the host already holds it.
    func bolusEventRaw(bolusId: Int) -> Data? {
        guard bolusId > 0, let serial = historyLogStoreSerial else {
            return nil
        }
        if let last = state.lastBolusEventRaw.flatMap(HistoryLogSyncIdentifier.decode), last.pumpSerial == serial,
           bolusId <= last.identifier
        {
            logger.warning("Bolus id \(bolusId) is not past \(last.identifier); keying the bolus on what was programmed")
            return nil
        }
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolusId)
        state.lastBolusEventRaw = raw
        return raw
    }

    /// How long before the pump's rate changes a temp basal is worked out against the larger of the
    /// two rates, about one host loop cycle.
    static let segmentChangeWindow: TimeInterval = .minutes(5)

    static let basalRateCheckTolerance: TimeInterval = .minutes(1)

    /// `pumpRate` is the rate the pump has in force. Within `segmentChangeWindow` of a change, the
    /// larger of it and the next: the temp then runs at most the request on either side, and the
    /// host, told the request, can only over-count until the change.
    func tempBasalBaseline(pumpRate: Double) -> Double {
        guard let change = pumpSegmentChanges(after: now, through: now.addingTimeInterval(Self.segmentChangeWindow)).first
        else {
            return pumpRate
        }
        return max(pumpRate, change.rate)
    }

    /// The pump runs a temp at `percent` of its own rate in force. Within one 0.01 U/hr step of
    /// that, unrounded or floored onto the reported grid: the pump's own rounding is not known.
    static func tempBasalReadbackMatches(_ readback: CurrentBasalStatusResponse, percent: Int) -> Bool {
        guard readback.basalType == .tempBasal else { return false }
        let exact = readback.profileBasalRate * Double(percent) / 100
        let floored = TandemPumpCapabilities.roundToSupportedBasalRate(exact)
        let actual = TandemPumpCapabilities.milliunits(readback.currentBasalRate)
        return [exact, floored].contains { abs(actual - TandemPumpCapabilities.milliunits($0)) <= 10 }
    }

    /// The pump runs something other than the percent it was sent. What runs is kept and reported
    /// at the pump's rate, so the host counts what goes in: stopping it would put the pump on its
    /// profile, which over-delivers whenever the temp was below it. The command still fails, since
    /// the host did not get the rate it asked for.
    private func rejectMismatchedTempBasal(
        _ readback: CurrentBasalStatusResponse,
        expectedRate: Double,
        percent: Int,
        duration: TimeInterval,
        tempRateId: Int,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        logger.error(
            "Pump reads back \(readback.currentBasalRate) U/hr (\(readback.basalType)) after a temp basal of \(expectedRate) U/hr"
        )
        let error = TandemPumpManagerValidationError.tempBasalRateMismatch(
            expected: expectedRate,
            actual: readback.currentBasalRate
        )

        switch readback.basalType {
        case .tempBasal:
            recordTempBasal(rate: readback.currentBasalRate, percent: percent, duration: duration, tempRateId: tempRateId)
        case .suspend:
            observeDeliveryState(.suspend)
        default:
            startScheduledBasalDose(reading: readback)
        }
        completion(.deviceState(error))
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
                    self.skewCompensationTemp = nil
                    self.logger.info("Current temp basal cancelled!")
                } else {
                    self.logger
                        .error(
                            "Failed to stop temp rate before suspending - Status: \(stopResponse?.status ?? -1)"
                        )
                }
            }

            let sentAt = self.now
            let response = self.bluetooth.write(SuspendPumpingRequest())
            guard let response, response.status == 0 else {
                self.logger.error("Failed to Suspend delivery - Status: \(response?.status ?? -1)")
                let isSuspended = self.readBackUnconfirmedSuspend(mayHaveApplied: response == nil, sentAt: sentAt)
                self.completeOnceTransitionIsReported { completion(isSuspended ? nil : PumpCommError.noResponse) }
                return
            }

            self.recordSuspend(sentAt: sentAt)
            self.logger.info("Insulin Delivery Suspended!")
            self.completeOnceTransitionIsReported { completion(nil) }
        }
    }

    /// Dated by the pump's record, or without history at the answer, or at the reading after a lost
    /// one: the later stop counts more insulin.
    private func recordSuspend(sentAt: Date) {
        settleDeliveryTransition()
        state.deliveryTransitions.interruptedTemp = nil
        if leaveCommandedTransitionForHistory(.suspend, sentAt: sentAt) {
            return
        }
        let suspendDose = UnfinalizedDose(suspendStartTime: now)
        var events = getActivePumpEvents(endDate: suspendDose.startDate)
        events.append(NewPumpEvent.suspend(dose: suspendDose.toDoseEntry(), date: suspendDose.startDate))

        state.basalDose = suspendDose
        state.lastReconciliation = now
        recordReportedTransition(
            .suspend,
            at: suspendDose.startDate,
            earliest: sentAt.addingTimeInterval(-Self.transitionMatchTolerance)
        )

        notifyDelegateStateUpdated()
        emitPumpEvents(events)
    }

    /// `write` gives nil for a lost answer and a refusal alike, so the suspend may have reached the
    /// pump; so may the temp stop before it, whatever its answer. Returns whether the pump is suspended.
    private func readBackUnconfirmedSuspend(mayHaveApplied: Bool, sentAt: Date) -> Bool {
        guard let status = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.warning("No basal status after an unconfirmed SuspendPumping; the next reading settles it")
            return false
        }
        let held = state.deliveryTransitions.pending?.observed ?? state.basalDose.type
        if mayHaveApplied, status.basalType == .suspend, held != .suspend {
            logger.warning("The pump is suspended though the SuspendPumping answer was lost; reporting the suspend")
            recordSuspend(sentAt: sentAt)
        } else {
            observeDeliveryState(status.basalType)
        }
        return status.basalType == .suspend
    }

    /// The pump can refuse a resume while its resume-pump alarms are unacknowledged, and a resume is
    /// what they ask for, so a refused one acknowledges them and retries once; other alarms are the user's.
    public func resumeDelivery(completion: @escaping (_ error: Error?) -> Void) {
        let completion = watchdogged(timeoutResult: PumpCommError.pumpNotConnected as Error?, completion)
        logger.info("Resume Insulin Delivery...")

        resumeAfterReadingPump(completion: completion) {
            ResumeWithAlarmAcknowledgement(
                sendResume: { self.sendResumePumping() },
                reloadNotifications: { self.fetchNotifications() },
                activeResumeAlarms: { self.notificationBundle.activeResumePumpAlarms() },
                acknowledgeAlarm: { alarm in
                    _ = self.acknowledgeNotification(type: .alarm, id: UInt32(alarm.rawValue))
                },
                log: { self.logger.info($0) }
            ).run()
        }
    }

    /// A stop the driver missed has to reach the host before the resume, or the host counts its temp
    /// basal as running until the resume and Loop ignores the suspend that arrives after it.
    private func resumeAfterReadingPump(completion: @escaping (Error?) -> Void, resume: @escaping () -> Error?) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to pump: \(error.localizedDescription)")
                completion(error)
                return
            }
            // A failed read still resumes: withholding insulin the user asked for is the worse error.
            guard let status = self.bluetooth.write(CurrentBasalStatusRequest()),
                  self.observeDeliveryState(status.basalType)
            else {
                let error = resume()
                self.completeOnceTransitionIsReported { completion(error) }
                return
            }
            self.afterHistoryIsReported {
                self.bluetooth.ensureConnected { error in
                    if let error {
                        completion(error)
                        return
                    }
                    let error = resume()
                    self.completeOnceTransitionIsReported { completion(error) }
                }
            }
            self.historyBackfillCoordinator.runTick()
        }
    }

    /// Sends a single `ResumePumpingRequest` and, once the pump has resumed, records the resume dose
    /// and notifies LoopKit. Returns nil once the pump is delivering or the error to report otherwise.
    ///
    /// Must be called while connected (i.e. inside `bluetooth.ensureConnected`).
    private func sendResumePumping() -> Error? {
        let sentAt = now
        let response = bluetooth.write(ResumePumpingRequest())
        guard let response, response.status == 0 else {
            logger.error("Failed to Resume delivery - Status: \(response?.status ?? -1)")
            let isDelivering = readBackUnconfirmedResume(mayHaveApplied: response == nil, sentAt: sentAt)
            return isDelivering ? nil : PumpCommError.noResponse
        }

        recordResume(at: now, sentAt: sentAt)
        return nil
    }

    /// Dated by the pump's record, or without history at the answer, or at the send after a lost one:
    /// the earlier start counts more insulin.
    private func recordResume(at date: Date, sentAt: Date) {
        settleDeliveryTransition()
        if leaveCommandedTransitionForHistory(.basal, sentAt: sentAt) {
            logger.info("Insulin Delivery Resumed!")
            return
        }
        var resumedAt = date
        if let host = hostTransition(before: .distantFuture), host.kind == .suspend {
            // Trio's IOB throws on a suspend and resume in the same second.
            resumedAt = max(resumedAt, host.date.addingTimeInterval(1))
        }
        let dose = UnfinalizedDose(
            resumeStartTime: resumedAt,
            insulinType: state.insulinType
        )
        var events = getActivePumpEvents(endDate: resumedAt)
        events.append(NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate))

        state.basalDose = dose
        state.lastReconciliation = max(resumedAt, now)
        recordReportedTransition(
            .resume,
            at: dose.startDate,
            latest: max(dose.startDate, now).addingTimeInterval(Self.transitionMatchTolerance)
        )

        notifyDelegateStateUpdated()
        emitPumpEvents(events)
        logger.info("Insulin Delivery Resumed!")
    }

    /// As `readBackUnconfirmedSuspend`, for a resume. Returns whether the pump is delivering.
    private func readBackUnconfirmedResume(mayHaveApplied: Bool, sentAt: Date) -> Bool {
        guard let status = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.warning("No basal status after an unconfirmed ResumePumping; the next reading settles it")
            return false
        }
        let held = state.deliveryTransitions.pending?.observed ?? state.basalDose.type
        if mayHaveApplied, status.basalType != .suspend, held == .suspend {
            logger.warning("The pump is delivering though the ResumePumping answer was lost; reporting the resume")
            recordResume(at: sentAt, sentAt: sentAt)
        } else {
            observeDeliveryState(status.basalType)
        }
        return status.basalType != .suspend
    }

    public func syncDeliveryLimits(
        limits: DeliveryLimits,
        completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void
    ) {
        let completion = watchdogged(timeoutResult: .failure(PumpCommError.pumpNotConnected), completion)
        logger.info("syncDeliveryLimits...")

        let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
        let basalRequest: SetMaxBasalLimitRequest?
        let bolusRequest: SetMaxBolusLimitRequest?
        do {
            basalRequest = try limits.maximumBasalRate.map {
                try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: Int(($0.doubleValue(for: hkUnit) * 1000.0).rounded()))
            }
            bolusRequest = try limits.maximumBolus.map {
                try SetMaxBolusLimitRequest(maxBolusMilliunits: Int(($0.doubleValue(for: HKUnit.internationalUnit()) * 1000.0).rounded()))
            }
        } catch {
            logger.error("Delivery limits rejected before sending: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sync delivery limits: \(error.localizedDescription)")
                completion(.failure(PumpCommError.pumpNotConnected))
                return
            }

            if let basalRequest {
                guard let basalResponse = self.bluetooth.write(basalRequest) else {
                    self.logger.error("Failed to set maxBasalLimit")
                    completion(.failure(PumpCommError.noResponse))
                    return
                }

                guard basalResponse.isStatusOK else {
                    self.logger.error("Failed to set maxBasalLimit - Status: \(basalResponse.status)")
                    completion(.failure(PumpRefusal.maximumBasalLimit(basalResponse, to: basalRequest)))
                    return
                }
            }

            if let bolusRequest {
                guard let bolusResponse = self.bluetooth.write(bolusRequest) else {
                    self.logger.error("Failed to set maxBolusLimit")
                    completion(.failure(PumpCommError.noResponse))
                    return
                }

                guard bolusResponse.isStatusOK else {
                    self.logger.error("Failed to set maxBolusLimit - Status: \(bolusResponse.status)")
                    completion(.failure(PumpRefusal.maximumBolusLimit(bolusResponse, to: bolusRequest)))
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

    func recoverAndReenterChangeCartridgeMode(completion: @escaping (EnterChangeCartridgeModeResponse?) -> Void) {
        logger.info("Backing out of any unfinished cartridge procedure, then re-entering change mode")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change mode recovery: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let recovery = CartridgeModeRecovery(
                exitFillTubing: { self.bluetooth.write(ExitFillTubingModeRequest())?.status },
                exitChangeCartridge: { self.bluetooth.write(ExitChangeCartridgeModeRequest())?.status },
                enterChangeCartridge: { self.bluetooth.write(EnterChangeCartridgeModeRequest()) },
                log: { self.logger.info($0) }
            )
            completion(recovery.run())
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

            let response = self.bluetooth.write(FillCannulaRequest(primeSizeMilliUnits: TandemPumpCapabilities.milliunits(amount)))

            completion(response)
        }
    }

    /// Records a cannula / infusion-set change. Call after the user successfully fills the cannula.
    /// Tracks the date in state and reports a site-change pump event to the host app via the delegate.
    /// `primeAmount`, when given, is the prime volume in units that was just delivered; it is
    /// remembered so the fill cannula wizard can pre-fill it next time, and reported as a `.prime`.
    func recordSiteChange(at date: Date? = nil, primeAmount: Double? = nil) {
        let date = date ?? now
        logger.info("Recording site change (cannula fill) at \(date)")
        state.lastSiteChangeDate = date
        if let primeAmount {
            state.lastCannulaFillAmount = primeAmount
        }
        notifyDelegateStateUpdated()
        let prime = primeAmount.map { [NewPumpEvent.cannulaPrime(units: $0, date: date)] } ?? []
        emitPumpEvents(prime + [NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
    }

    /// Call once the pump has left fill tubing mode after insulin flowed.
    func recordTubingFill(at date: Date? = nil) {
        let date = date ?? now
        logger.info("Recording tubing fill at \(date)")
        emitPumpEvents([NewPumpEvent.tubingPrime(date: date)], replacePendingEvents: false)
    }

    /// Records a cartridge / reservoir change. Call after the user successfully changes the cartridge.
    /// Tracks the date in state and reports the change as a pump event to the host app via the delegate.
    func recordCartridgeChange(at date: Date? = nil) {
        let date = date ?? now
        logger.info("Recording cartridge change at \(date)")
        state.lastCartridgeChangeDate = date
        notifyDelegateStateUpdated()
        emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
    }

    public func syncPumpTime(completion: @escaping (Result<Void, PumpManagerError>) -> Void) {
        writePumpTime { error in
            if let error {
                completion(.failure(error))
                return
            }

            self.syncPumpData { _ in
                completion(.success(()))
            }
        }
    }

    func writePumpTime(completion: @escaping (PumpManagerError?) -> Void) {
        logger.info("Syncing pump time")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for change datetime: \(error.localizedDescription)")
                completion(PumpManagerError.communication(PumpCommError.pumpNotConnected))
                return
            }

            // Read first: setup writes the clock before any sync has measured it.
            let offset = self.bluetooth.write(TimeSinceResetRequest()).map { $0.currentTimeDate.timeIntervalSince(self.now) }
                ?? (self.state.currentPumpTime == nil ? nil : self.state.pumpClockOffset)
            let epoch = Dates.fromInstantToJan12008EpochSeconds(self.now)

            let request = ChangeTimeDateRequest(tandemEpochTime: UInt32(epoch))
            guard let response = self.bluetooth.write(request) else {
                self.logger.error("Failed to change datetime")
                completion(PumpManagerError.communication(PumpCommError.noResponse))
                return
            }

            guard response.isStatusOK else {
                let error = PumpCommError.errorResponse(
                    context: String(
                        localized: "Error syncing time with pump",
                        comment: "Message when pump rejects ChangeTimeDateRequest"
                    ),
                    request: request,
                    response: response
                )
                completion(PumpManagerError.communication(error))
                return
            }

            if let offset {
                self.reportPumpClockAdjustment(by: -offset)
            } else {
                self.logger.warning("Pump clock set without a reading of it; no adjustment to report")
            }
            completion(nil)
        }
    }

    func pairPump(code: String, peripheral: CBPeripheral, completion: @escaping (Error?) -> Void) {
        state.pumpState.pincode = code
        bluetooth.connect(peripheral) { [weak self] error in
            // A code the pump refused is not kept for a later attempt to reuse, unless a newer attempt has replaced it.
            if error != nil, self?.state.pumpState.pincode == code {
                self?.state.pumpState.pincode = nil
            }
            completion(error)
        }
    }

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        logger.debug("Preparing for pump deactivation – tearing down transport")
        #if TANDEMKIT_VIRTUAL_PUMP
        VirtualPumpControl.detach(self)
        #endif
        bluetooth.deactivate()
        telemetryScheduler.cancelAll()
        finalizeHeldDosesForDeactivation()

        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }

    /// A setup flow left before the host was handed the manager (#603). Nothing owns it from here, so
    /// its link goes down for good: left up, it kept reconnecting to the pump it paired and held the
    /// pump's one link against every attempt after it.
    func abandonSetup() {
        logger.info("Setup left before a host adopted the pump manager; tearing down transport")
        bluetooth.deactivate()
        telemetryScheduler.cancelAll()
    }

    /// The pump runs a temp basal to its end and finishes a bolus after the app forgets it. Loop stores a
    /// finalized dose only once it has ended, so the temp is cut now and its remainder reported on its own.
    func finalizeHeldDosesForDeactivation() {
        settleDeliveryTransition()
        let removed = state.lastPumpSerial.map { _ in NewPumpEvent.pumpRemoved(date: now) }
        let heldExtendedParts = deactivatedExtendedPartEvents()
        guard state.basalDose.type == .tempBasal || state.bolusDose != nil || state.pendingBolusFinalization != nil
            || !heldExtendedParts.isEmpty
        else {
            if let removed {
                logger.info("Pump manager deactivating; reporting the pump removed")
                emitPumpEvents([removed], replacePendingEvents: false)
            }
            return
        }

        var events: [NewPumpEvent] = []
        if state.basalDose.type == .tempBasal {
            let end = state.basalDose.estimatedEndDate
            // A second on at least: Trio orders two rows in one second arbitrarily.
            let cut = max(now, state.basalDose.startDate.addingTimeInterval(1))
            events += getActivePumpEvents(endDate: cut)
            let running = state.basalDose
            if cut < end, running.type == .tempBasal {
                let remainder = UnfinalizedDose(
                    tempRate: running.value,
                    duration: end.timeIntervalSince(cut),
                    automatic: running.automatic,
                    insulinType: running.insulinType,
                    startDate: cut,
                    tempRateId: running.tempRateId,
                    tempPercent: running.tempPercent
                )
                let (finished, last) = splitAtSegmentChanges(remainder, through: end, partOf: running.eventRaw)
                events += finished
                events.append(NewPumpEvent.tempBasal(dose: last.toDoseEntry(isMutable: false, endDate: end, now: now), of: last))
            }
            state.basalDose = UnfinalizedDose(basalRate: scheduledBasalRateInForce(at: end), insulinType: state.insulinType, startDate: end)
        }

        var bolusRaws = Set<Data>()
        for dose in [state.bolusDose, state.pendingBolusFinalization].compactMap({ $0 }) {
            let record = dose.bolusId.flatMap { historyBolusReport(bolusId: $0, startedAt: dose.startDate) }
            if let record {
                dose.deliveredUnits = record.deliveredUnits
            } else if dose === state.bolusDose {
                dose.deliveredUnits = dose.value
            }
            let end = BolusEndDate.resolve(
                startDate: dose.startDate,
                deliveryStartDate: dose.deliveryStartDate,
                deliveredUnits: dose.deliveredUnits,
                pumpTimestamp: record.map { hostDate(forPumpDate: $0.pumpTimestamp) },
                detectedAt: now
            )
            let event = NewPumpEvent.bolus(dose: dose.toDoseEntry(endDate: end, now: now), of: dose)
            if bolusRaws.insert(event.raw).inserted {
                events.append(event)
            }
        }
        events += heldExtendedParts
        state.bolusDose = nil
        state.pendingBolusFinalization = nil
        state.bolusState = .noBolus
        bolusProgressReport = nil
        state.lastReconciliation = now

        logger.info("Pump manager deactivating; reporting \(events.count) held dose event(s) finalized")
        notifyDelegateStateUpdated()
        emitPumpEvents((events + [removed].compactMap { $0 }).sorted { $0.date < $1.date })
    }

    /// Called by whichever connect brought the session up. The pump's qualifying events are lost while
    /// the link is down, so what it did meanwhile reaches the host only through a sync.
    func didReconnect() {
        // The host's first poll syncs; a sync that reconnected is in flight, and this joins it.
        guard canNotifyDelegate else {
            return
        }
        logger.info("Reconnected; syncing")
        syncPumpData(onlyIfIdle: true, completion: nil)
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
        // The pump paired next may be another, whose serial and settings would otherwise wait a day.
        state.lastSettingsCheckedAt = nil
        state.hasSyncedBasalRateSchedule = false
        state.basalRateMismatchDetectedAt = nil
        state.basalProfileUpdateFailed = false
        notifyDelegateStateUpdated()
    }

    func setPumpSound(request: SetPumpSoundsRequest, completion: @escaping (Bool) -> Void) {
        logger.info("Setting pump sounds...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sound settings: \(error.localizedDescription)")
                completion(false)
                return
            }

            let response = self.bluetooth.write(request)
            let accepted = response?.isStatusOK ?? false
            if !accepted {
                let reason = response.map { "status \($0.status)" } ?? "no response"
                self.logger.error("Failed to set pump sounds: \(reason)")
            }

            // Allow the patch to set values
            Thread.sleep(forTimeInterval: .seconds(1))
            self.fetchGlobalPumpSettings()

            completion(accepted)
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

    /// Units mode only (#428): carbs mode doses from the pump's own carb ratio, which is never
    /// synced, and the carbs never reach the host.
    func setQuickBolusSettings(
        enabled: Bool,
        incrementUnits: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard SetQuickBolusSettingsRequest.supportedIncrementUnits.contains(incrementUnits) else {
            logger.error("Refusing unsupported quick bolus increment: \(incrementUnits) mU")
            completion(false)
            return
        }

        logger.info("Setting quick bolus...")

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for quick bolus: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let current = self.fetchGlobalPumpSettings() else {
                completion(false)
                return
            }

            let request = Self.quickBolusSettingsChange(from: current, enabled: enabled, incrementUnits: incrementUnits)
            guard !request.changedFields.isEmpty else {
                completion(true)
                return
            }

            guard let response = self.bluetooth.write(request) else {
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
            guard let updated = self.fetchGlobalPumpSettings() else {
                completion(false)
                return
            }

            let applied = Self.quickBolusSettingsChange(from: updated, enabled: enabled, incrementUnits: incrementUnits)
            guard applied.changedFields.isEmpty else {
                self.logger.error("Pump accepted the quick bolus change but still reports \(updated)")
                completion(false)
                return
            }

            completion(true)
        }
    }

    /// Carries the pump's current values in every field it is not asked to change, as the Tandem app does.
    static func quickBolusSettingsChange(
        from current: PumpGlobalsResponse,
        enabled: Bool,
        incrementUnits: Int
    ) -> SetQuickBolusSettingsRequest {
        var changedFields: QuickBolusSettingsFields = []
        if current.isQuickBolusEnabled() != enabled {
            changedFields.insert(.enabled)
        }
        if enabled, current.quickBolusEntryType != QuickBolusMode.units.rawValue {
            changedFields.insert(.mode)
        }
        if enabled, current.quickBolusIncrementUnits != incrementUnits {
            changedFields.insert(.incrementUnits)
        }

        return SetQuickBolusSettingsRequest(
            enabled: enabled,
            mode: enabled ? .units : QuickBolusMode(rawValue: current.quickBolusEntryType) ?? .units,
            incrementUnits: enabled ? incrementUnits : current.quickBolusIncrementUnits,
            incrementCarbs: current.quickBolusIncrementCarbs,
            changedFields: changedFields
        )
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
                self.settleDeliveryTransition()

                let dose = UnfinalizedDose(
                    basalRate: self.scheduledBasalRateInForce(),
                    insulinType: self.state.insulinType,
                    startDate: self.now
                )
                var events = self.getActivePumpEvents(endDate: dose.startDate)
                events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))

                self.state.basalDose = dose
                self.state.lastReconciliation = self.now
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
            if !request.enabled, self.state.useControlIQ {
                self.state.controlIQEndedAt = self.now
            }
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

    /// Writes one sleep schedule slot, flagging the fields that differ from what the pump holds, then
    /// reads the schedules back. The pump answers OK and keeps a field it is sent unflagged. The
    /// read-back, when the pump answers it, is what the pump holds.
    func setSleepSchedule(
        slot: Int,
        schedule: ControlIQSleepScheduleResponse.SleepSchedule,
        completion: @escaping (Error?, ControlIQSleepScheduleResponse?) -> Void
    ) {
        logger.info("Setting sleep schedule \(slot)")

        guard supports(SetSleepScheduleRequest.self) else {
            logger.error("Pump does not support setting sleep schedules")
            completion(SleepScheduleWriteError.unsupported, nil)
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for sleep schedule: \(error.localizedDescription)")
                completion(error, nil)
                return
            }

            guard let current = self.bluetooth.write(ControlIQSleepScheduleRequest()),
                  let previous = current.schedule(at: slot)
            else {
                self.logger.error("Failed to read sleep schedules before setting one")
                completion(SleepScheduleWriteError.noResponse, nil)
                return
            }

            guard previous != schedule else {
                completion(nil, current)
                return
            }

            guard let response = self.bluetooth.write(SetSleepScheduleRequest(
                slot: slot,
                previous: previous,
                updated: schedule
            )) else {
                self.logger.error("Failed to set sleep schedule")
                completion(SleepScheduleWriteError.noResponse, nil)
                return
            }

            let readBack = self.bluetooth.write(ControlIQSleepScheduleRequest())

            guard response.isStatusOK else {
                self.logger.error("Failed to set sleep schedule - Status: \(response.status)")
                completion(SleepScheduleWriteError.pumpRejected(status: response.status), readBack)
                return
            }

            if let held = readBack?.schedule(at: slot), held != schedule {
                self.logger.error("Sleep schedule \(slot) reads back as \(held) after writing \(schedule)")
                completion(SleepScheduleWriteError.notApplied, readBack)
                return
            }

            completion(nil, readBack)
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
        if events.contains(.bolusChange) {
            // A pump-UI bolus reaches the host only through history, so read and report it now
            // rather than at the next sync, a loop cycle or more out of IOB.
            historyBackfillCoordinator.runTick()
        }

        let fetches = QualifyingEventFetch.fetches(for: events, context: context)
        guard !fetches.isEmpty else {
            // Nothing to fetch (e.g. bg only) — don't spin up a command job just to
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
            if self.state.deliveryTransitions.pending != nil {
                self.historyBackfillCoordinator.runTick()
            }

            completion()
        }
    }

    /// The pump state the suggested handlers are selected against. PumpX2 reads the equivalent
    /// out of its global `PumpStateSupplier`.
    var qualifyingEventContext: QualifyingEventContext {
        QualifyingEventContext(
            apiVersion: state.pumpState.apiVersion,
            pumpModel: state.pumpState.pumpModel,
            // Only a pump with Control-IQ answers its info read, whether it is on or off.
            controlIQSupported: state.controlIQEnabled != nil,
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
        case .insulinDuration:
            fetchInsulinDuration()
        case .insulinOnBoard:
            fetchInsulinOnBoard()
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
    /// Closes out a running temp basal dose at `now` and records scheduled basal from `now`.
    func startScheduledBasalDose(reading: CurrentBasalStatusResponse? = nil) {
        settleDeliveryTransition()
        let dose = UnfinalizedDose(basalRate: scheduledBasalRateInForce(reading: reading), insulinType: state.insulinType, startDate: now)

        var events = getActivePumpEvents(endDate: dose.startDate)
        events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(isMutable: false), date: dose.startDate))

        state.deliveryTransitions.interruptedTemp = nil
        state.basalDose = dose
        state.lastReconciliation = now

        notifyDelegateStateUpdated()
        emitPumpEvents(events)
    }

    func getActivePumpEvents(endDate: Date? = nil) -> [NewPumpEvent] {
        // Until history dates a change the pump made, the host holds the dose it ended as last reported
        // and uncut. A caller ending the temp at `endDate` settles the change first.
        if endDate == nil, let held = state.deliveryTransitions.pending?.prior {
            guard held.type == .tempBasal else { return [] }
            return [NewPumpEvent.tempBasal(dose: held.toDoseEntry(isMutable: true, now: now), of: held)]
        }
        guard state.basalDose.type == .tempBasal else {
            return []
        }

        let (finished, running) = splitAtSegmentChanges(state.basalDose, through: endDate ?? now)
        if !finished.isEmpty {
            state.basalDose = running
            notifyDelegateStateUpdated()
        }

        let basalEntry = state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? now, now: now)
        var events = finished + [
            NewPumpEvent.tempBasal(dose: basalEntry, of: state.basalDose)
        ]

        // Every caller reports its own change at `endDate`; Trio orders two rows in one second arbitrarily.
        if let endDate, basalEntry.endDate == state.basalDose.estimatedEndDate, endDate.timeIntervalSince(basalEntry.endDate) >= 1 {
            let dose = UnfinalizedDose(
                basalRate: scheduledBasalRateInForce(at: basalEntry.endDate),
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

    /// Every bolus the host holds as mutable, as it was last reported: a replacing batch that
    /// leaves one out deletes it, and Loop never revives a deleted dose (#330).
    func inProgressBolusEvents() -> [NewPumpEvent] {
        let events = [state.bolusDose, state.pendingBolusFinalization].compactMap { dose in
            dose.map { NewPumpEvent.bolus(dose: $0.toDoseEntry(isMutable: true), of: $0) }
        } + heldExtendedPartEvents()
        var seen = Set<Data>()
        return events.filter { seen.insert($0.raw).inserted }
    }

    func emitPumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool = true) {
        var events = events
        if replacePendingEvents {
            let reported = Set(events.map(\.raw))
            events += inProgressBolusEvents().filter { !reported.contains($0.raw) }
        }

        for event in events {
            guard let dose = event.dose, dose.type == .bolus, !dose.isMutable else {
                continue
            }
            state.bolusReportLedger.markFinalized(raw: event.raw, units: dose.deliveredUnits ?? dose.programmedUnits)
        }
        let heldTemp = state.basalDose
        state.reportedBasal.record(events, replacePendingEvents: replacePendingEvents) { dose in
            heldTemp.type == .tempBasal && dose.startDate >= heldTemp.startDate ? heldTemp.tempRateId : nil
        }

        emitPumpEvents(PendingPumpEventBatch(
            events: events,
            lastReconciliation: reconciliationBoundary,
            replacePendingEvents: replacePendingEvents
        ))
    }

    /// `lastReconciliation` as the host is given it. Loop takes delivery up to it as accounted for, so
    /// it stops at a pump bolus history has yet to report; released by the batch that reports it.
    var reconciliationBoundary: Date? {
        guard state.featureFlags.historyDoseReporting,
              let hold = state.bolusReportLedger.boundaryHold(pumpSerial: historyLogStoreSerial?.rawValue)
        else {
            return state.lastReconciliation
        }
        return state.lastReconciliation.map { min($0, hold) }
    }

    func reportReconciliationBoundary() {
        emitPumpEvents([], replacePendingEvents: false)
    }

    /// Every dose the host holds as mutable, re-sent as the complete pending set so a sync refreshes
    /// a running dose. Loop ignores a non-replacing re-send of a `raw` it holds.
    func reportPendingDoses() {
        let events = getActivePumpEvents()
        // An empty replacing batch purges every mutable row in Trio and nothing in Loop.
        guard !events.isEmpty || !inProgressBolusEvents().isEmpty else {
            reportReconciliationBoundary()
            return
        }
        emitPumpEvents(events)
    }

    private func emitPumpEvents(_ batch: PendingPumpEventBatch) {
        guard canNotifyDelegate else {
            logger.warning("No pump delegate; holding \(batch.events.count) pump event(s) until one attaches")
            holdPumpEventBatches([batch])
            return
        }

        deliverPumpEventBatches(takePendingPumpEventBatches() + [batch])
    }

    /// How far the driver moved the pump's clock, in seconds: negative when it ran ahead. MinimedKit
    /// passes the drift, the other sign; Loop and Trio only log it.
    func reportPumpClockAdjustment(by adjustment: TimeInterval) {
        logger.info("Pump clock adjusted by \(adjustment) s")
        pendingPumpClockAdjustmentLock.lock()
        pendingPumpClockAdjustments.append(adjustment)
        pendingPumpClockAdjustmentLock.unlock()
        flushPendingPumpClockAdjustments()
    }

    private func flushPendingPumpClockAdjustments() {
        guard canNotifyDelegate else { return }

        pendingPumpClockAdjustmentLock.lock()
        let adjustments = pendingPumpClockAdjustments
        pendingPumpClockAdjustments = []
        pendingPumpClockAdjustmentLock.unlock()
        guard !adjustments.isEmpty else { return }

        pumpDelegate.notify { delegate in
            for adjustment in adjustments {
                delegate?.pumpManager(self, didAdjustPumpClockBy: adjustment)
            }
        }
    }

    func flushPendingPumpEvents() {
        guard canNotifyDelegate else { return }

        let batches = takePendingPumpEventBatches()
        guard !batches.isEmpty else { return }

        logger.info("Delegate attached; replaying \(batches.count) held pump event batch(es)")
        deliverPumpEventBatches(batches)
    }

    /// The host asserts its delegate methods run on the queue it set, so a delegate without a
    /// queue is not somewhere events can be sent. Also whether a host has adopted the manager at all.
    var canNotifyDelegate: Bool {
        pumpDelegate.delegate != nil && hasDelegateQueue
    }

    private func deliverPumpEventBatches(_ batches: [PendingPumpEventBatch]) {
        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                // Front, to keep the emission order.
                self.holdPumpEventBatches(batches, atFront: true)
                return
            }

            for batch in batches {
                #if TANDEMKIT_VIRTUAL_PUMP
                let logged = VirtualPumpControl.willDeliver(
                    batch.events,
                    lastReconciliation: batch.lastReconciliation,
                    replacePendingEvents: batch.replacePendingEvents,
                    hostNow: self.clock.now,
                    from: self
                )
                let completion: (Error?) -> Void = { VirtualPumpControl.delegateDidFinish(logged, error: $0, from: self) }
                #else
                let completion: (Error?) -> Void = { _ in }
                #endif
                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: batch.events,
                    lastReconciliation: batch.lastReconciliation,
                    replacePendingEvents: batch.replacePendingEvents,
                    completion: completion
                )
            }
        }
    }

    private func holdPumpEventBatches(_ batches: [PendingPumpEventBatch], atFront: Bool = false) {
        pendingPumpEventLock.lock()
        defer { pendingPumpEventLock.unlock() }

        if atFront {
            pendingPumpEventBatches.insert(contentsOf: batches, at: 0)
        } else {
            pendingPumpEventBatches += batches
        }

        // Drop the oldest: a later batch is the more current picture of delivery.
        let overflow = pendingPumpEventBatches.count - TandemPumpManager.maximumHeldPumpEventBatches
        if overflow > 0 {
            logger.error("Held pump event batches overflowed; dropping the \(overflow) oldest")
            pendingPumpEventBatches.removeFirst(overflow)
        }
    }

    private func takePendingPumpEventBatches() -> [PendingPumpEventBatch] {
        pendingPumpEventLock.lock()
        defer { pendingPumpEventLock.unlock() }

        let batches = pendingPumpEventBatches
        pendingPumpEventBatches = []
        return batches
    }

    /// Test seam.
    internal var heldPumpEventBatchCount: Int {
        pendingPumpEventLock.lock()
        defer { pendingPumpEventLock.unlock() }
        return pendingPumpEventBatches.count
    }

    func getScheduledBasalRate(at date: Date? = nil) -> Double {
        hostBasalSchedule.rate(at: date ?? now)
    }

    /// A `.basal` marker's rate: a `reading`'s profile rate, else the host's schedule on the pump's
    /// clock. Skewed, the host's own, which the clock skew temp runs.
    func scheduledBasalRateInForce(at date: Date? = nil, reading: CurrentBasalStatusResponse? = nil) -> Double {
        let date = date ?? now
        if state.isPumpClockSkewed {
            return getScheduledBasalRate(at: date)
        }
        if let reading, reading.basalType != .suspend {
            return reading.profileBasalRate
        }
        return getScheduledBasalRate(at: date.addingTimeInterval(state.pumpClockOffset))
    }

    var hostBasalSchedule: HostBasalSchedule {
        HostBasalSchedule(state.basalRateSchedule)
    }

    /// The pump rescales a temp at each segment change, and neither host revises a temp basal once
    /// it is reported finished, so every path that finishes one cuts it here first: the parts
    /// finished at changes before `end`, and the part running at `end` at `tempPercent` of its rate.
    /// `partOf` is the part of the temp rate `dose` continues, whose next parts the cuts are: `dose`
    /// itself unless it is a piece of its own.
    func splitAtSegmentChanges(
        _ dose: UnfinalizedDose,
        through end: Date,
        partOf: Data? = nil
    ) -> (finished: [NewPumpEvent], running: UnfinalizedDose) {
        guard dose.type == .tempBasal, let percent = dose.tempPercent, percent > 0 else {
            return ([], dose)
        }

        var running = dose
        var part = partOf ?? dose.eventRaw
        var finished: [NewPumpEvent] = []
        for change in pumpSegmentChanges(after: dose.startDate, through: min(end, dose.estimatedEndDate))
            where change.date < dose.estimatedEndDate
        {
            let rate = roundToSupportedBasalRate(unitsPerHour: change.rate * Double(percent) / 100)
            guard Int((rate * 1000).rounded()) != Int((running.value * 1000).rounded()) else { continue }

            let entry = running.toDoseEntry(isMutable: false, endDate: change.date, now: now)
            finished.append(NewPumpEvent.tempBasal(dose: entry, of: running))
            part = part.flatMap(HistoryLogSyncIdentifier.nextTempRatePart(after:))
            running = UnfinalizedDose(
                tempRate: rate,
                duration: dose.estimatedEndDate.timeIntervalSince(change.date),
                automatic: dose.automatic,
                insulinType: dose.insulinType,
                startDate: change.date,
                tempRateId: dose.tempRateId,
                tempPercent: percent,
                eventRaw: part
            )
        }
        if !finished.isEmpty {
            logger.info("Temp basal at \(percent)% crossed \(finished.count) pump segment change(s); now \(running.value) U/hr")
        }
        return (finished, running)
    }

    /// Reports the cut as soon as a reading sees the temp still running past a change. Not one the
    /// pump has replaced, which history ends before the change.
    func reportTempBasalSegmentChanges() {
        guard state.basalDose.type == .tempBasal, state.deliveryTransitions.pending?.replacement == nil else { return }
        let events = getActivePumpEvents()
        guard events.count > 1 else { return }
        emitPumpEvents(events)
    }

    /// Where the pump's rate changes after `start` through `end`, dated on the phone's clock. Reads
    /// the host's schedule on the pump's clock, which is the pump's profile whenever temp basals are
    /// allowed at all.
    func pumpSegmentChanges(after start: Date, through end: Date) -> [(date: Date, rate: Double)] {
        let items = state.basalRateSchedule.items.sorted { $0.startTime < $1.startTime }
        guard items.count > 1, end > start else { return [] }

        let offset = state.pumpClockOffset
        guard TandemPumpManagerState.trustsPumpClockOffset(offset) else { return [] }

        let pumpStart = start.addingTimeInterval(offset)
        let startOfDay = Calendar.current.startOfDay(for: pumpStart)
        var rate = getScheduledBasalRate(at: pumpStart)
        var changes: [(date: Date, rate: Double)] = []

        for day in 0 ... Int(end.timeIntervalSince(start) / .days(1)) + 1 {
            for item in items {
                let pumpDate = startOfDay.addingTimeInterval(.days(Double(day)) + item.startTime)
                let date = pumpDate.addingTimeInterval(-offset)
                guard date > start else { continue }
                guard date <= end else { return changes }
                if Int((item.value * 1000).rounded()) != Int((rate * 1000).rounded()) {
                    changes.append((date, item.value))
                    rate = item.value
                }
            }
        }
        return changes
    }
}

extension TandemPumpManager {
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

        let completion: ((any Error)?) -> Void = { error in
            if error != nil {
                self.issueAgainAfterFailedAcknowledgement(alertIdentifier)
            }
            completion(error)
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

/// The resume-with-alarm-acknowledgement sequence `resumeDelivery` runs.
///
/// Split out of `TandemPumpManager` so the branching — the ways a resume can end — is unit-testable
/// without a BLE stack; `TandemPumpManager.resumeDelivery` supplies the real pump operations. Like
/// the manager's own command bodies, every operation here is synchronous and must run on the pump
/// command queue with the pump already connected.
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
        queue.asyncAfter(wallInterval: timeout, execute: item)
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

/// One sync's `lastSync`, for the polls that found it in flight. Only the first `set` counts.
final class SyncResult {
    private let lock = NSLock()
    private var lastSync: Date??
    private var waiters: [(Date?) -> Void] = []

    func whenSet(_ waiter: @escaping (Date?) -> Void) {
        lock.lock()
        guard let lastSync else {
            waiters.append(waiter)
            lock.unlock()
            return
        }
        lock.unlock()
        waiter(lastSync)
    }

    func set(_ value: Date?) {
        lock.lock()
        guard lastSync == nil else {
            lock.unlock()
            return
        }
        lastSync = .some(value)
        let waiters = waiters
        self.waiters = []
        lock.unlock()
        waiters.forEach { $0(value) }
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
