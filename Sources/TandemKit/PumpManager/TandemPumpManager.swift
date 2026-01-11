import CoreBluetooth
import Dispatch
import Foundation
#if canImport(HealthKit)
    import HealthKit
#endif
import LoopKit
import TandemBLE
import TandemCore
#if canImport(UIKit)
    import UIKit
#endif

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

// Simple Locked wrapper
public class Locked<Value> {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

private struct ActiveBolus {
    let id: Int
    let dose: UnfinalizedDose
}

private struct ActiveTempBasal {
    let dose: DoseEntry
    let scheduledRate: Double
}

@available(macOS 13.0, iOS 14.0, *) public class TandemPumpManager: PumpManager, Pluggable {
    public static var pluginIdentifier: String = "TandemPumpManager"

    public var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    public typealias RawStateValue = [String: Any]

    // Tandem Mobi and t:slim X2: max 16 basal segments
    public static var onboardingMaximumBasalScheduleEntryCount: Int = 16

    // Tandem Mobi and t:slim X2: 0.01 - 15.00u/hr
    public static var onboardingSupportedBasalRates: [Double] = Array(stride(from: 0.01, through: 15.0, by: 0.01))

    // Tandem Mobi and t:slim X2: 0.05 - 25.00 unit bolus
    public static var onboardingSupportedBolusVolumes: [Double] = Array(stride(from: 0.05, through: 25.0, by: 0.01))

    public static var onboardingSupportedMaximumBolusVolumes: [Double] = Array(stride(from: 0.05, through: 25.0, by: 0.01))

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    public let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    public let tandemPump: TandemPump
    private let log = TandemLogger(category: "TandemPumpManager")
    private let telemetryLogger = TandemLogger(category: "TandemPumpManager.Telemetry")
    private let notificationRouter = PumpNotificationRouter()
    private let notificationLogger = TandemLogger(category: "TandemPumpManager.Notifications")
    private let historyFetchQueue = DispatchQueue(label: "com.loopkit.TandemKit.HistoryFetchQueue")
    private let historyDeduplicator = HistoryDeduplicator()
    private let historyTimestampReconciler = HistoryTimestampReconciler()
    private let historyMapper = HistoryToDoseMapper()
    private let historyReconciler = HistoryReconciler()
    private let telemetryScheduler = PumpTelemetryScheduler(label: "com.loopkit.TandemKit.TelemetryScheduler")
    private var historyTelemetryInterval: TimeInterval = 5 * 60

    // Status tracking
    private let statusObservers = Locked<[UUID: (observer: PumpManagerStatusObserver, queue: DispatchQueue)]>([:])
    private let scanDeviceObservers = WeakSynchronizedSet<StateObserver>()
    private let inScanningMode = Locked<Bool>(false)
    private let lockedStatus: Locked<PumpManagerStatus>
    private let sessionInitializationQueue = DispatchQueue(label: "com.jwoglom.TandemKit.sessionInit")
    private let needsSessionInitialization = Locked<Bool>(false)
    private let sessionBootstrapInProgress = Locked<Bool>(false)
    private let sessionBootstrapRetryAttempt = Locked<Int>(0)
    private let activeBolus = Locked<ActiveBolus?>(nil)
    private let activeTempBasal = Locked<ActiveTempBasal?>(nil)
    private let activeHistoryFetchSession = Locked<HistoryFetchSession?>(nil)
    private let lockedBatteryChargeRemaining: Locked<Double?>
    private let lockedReservoirValue: Locked<ReservoirValue?>
    private var bolusProgressReport: TandemDoseProgressReporter?
    private var telemetryConfigured = false
    private weak var activePeripheralManager: PeripheralManager?
    private var targetPeripheralIdentifier: UUID?

    private func updatePairingArtifacts(with pumpState: PumpState?) {
        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            let derivedSecret = pumpState?.derivedSecret
            let serverNonce = pumpState?.serverNonce
            PumpStateSupplier.storePairingArtifacts(derivedSecret: derivedSecret, serverNonce: serverNonce)
        #endif

        // Set the timeSinceReset closure to provide the value from pump state
        PumpStateSupplier.pumpTimeSinceReset = { [weak self] in
            self?.lockedState.value.pumpState?.timeSinceReset ?? 0
        }
    }

    private func configureStateSuppliers() {
        PumpStateSupplier.currentBolusId = { [weak self] in
            self?.activeBolus.value?.id
        }
    }

    private func clearStalePairingArtifactsIfNeeded() {
        var currentState = lockedState.value
        guard var pumpState = currentState.pumpState,
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
        currentState.pumpState = pumpState
        lockedState.value = currentState
        pumpComm.syncPumpState(currentState.pumpState)
        updatePairingArtifacts(with: pumpState)
    }

    private func resetManagerStateAfterDeactivation() {
        telemetryLogger.debug("Resetting stored pump state after deactivation")
        let now = Date()
        updateStatus { status in
            status.pumpBatteryChargeRemaining = nil
            status.bolusState = .noBolus
            status.basalDeliveryState = .suspended(now)
            status.deliveryIsUncertain = true
        }

        lockedBatteryChargeRemaining.value = nil
        lockedReservoirValue.value = nil
        activeBolus.value = nil
        activeTempBasal.value = nil

        var managerState = lockedState.value
        managerState.pumpState = nil
        managerState.lastReconciliation = nil
        managerState.lastReservoirReading = nil
        managerState.lastBatteryReading = nil
        managerState.lastBasalStatusDate = nil
        managerState.latestInsulinOnBoard = nil
        managerState.basalRateSchedule = nil
        lockedState.value = managerState

        needsSessionInitialization.value = false

        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)
        #endif
        PumpStateSupplier.pumpTimeSinceReset = { 0 }

        let refreshedPumpComm = PumpComm(pumpState: nil, retryPolicy: pumpComm.retryPolicy)
        refreshedPumpComm.delegate = self
        tandemPump.pumpComm = refreshedPumpComm

        notifyPumpManagerDelegateDidUpdateState()
    }

    func setHistoryTelemetryIntervalForTesting(_ interval: TimeInterval) {
        historyTelemetryInterval = interval
        telemetryConfigured = false
        ensureCurrentPumpData { _ in }
    }

    private func performScheduledHistoryFetch() {
        guard hasPairedPumpState else {
            telemetryLogger.debug("Skipping history telemetry – pump not paired")
            return
        }

        guard transportLock.value != nil else {
            telemetryLogger.debug("Skipping history telemetry – no transport available")
            return
        }

        guard activeHistoryFetchSession.value == nil else {
            telemetryLogger.debug("Skipping history telemetry – fetch already in progress")
            return
        }

        telemetryLogger.debug("[telemetry] Fetching pump history")
        fetchPumpHistory { [weak self] error in
            if let error {
                self?.telemetryLogger.error("[telemetry] History fetch failed: \(error)")
            } else {
                self?.telemetryLogger.debug("[telemetry] History fetch completed")
            }
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    private var pumpComm: PumpComm {
        get {
            tandemPump.pumpComm
        }
        set {
            tandemPump.pumpComm = newValue
        }
    }

    public func updateTransport(_ transport: PumpMessageTransport?) {
        if let transport = transport {
            let instanceId = ObjectIdentifier(transport as AnyObject)
            log.info("updateTransport: setting transport instance=\(instanceId)")
        } else {
            log.info("updateTransport: clearing transport (nil)")
        }
        transportLock.value = transport

        if let peripheralManager = activePeripheralManager, transport != nil {
            pumpComm.manager = peripheralManager
        } else if transport == nil {
            pumpComm.manager = nil
        }

        if let activeTransport = transport {
            telemetryLogger.debug("Transport available – checking authentication before telemetry")
            updateStatus { status in
                status.deliveryIsUncertain = false
            }

            // Only trigger telemetry if we're already authenticated
            if let pumpState = lockedState.value.pumpState,
               pumpState.derivedSecret != nil,
               pumpState.serverNonce != nil
            {
                bootstrapAuthenticatedSessionIfNeeded(on: activeTransport)
            } else {
                telemetryLogger.debug("Not authenticated yet – skipping telemetry until pairing completes")
            }
        } else {
            telemetryLogger.debug("Transport cleared – telemetry will pause until reconnect")
            updateStatus { status in
                status.deliveryIsUncertain = true
            }
            needsSessionInitialization.value = lockedState.value.pumpState?.valid == true
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
        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            guard let pumpState = lockedState.value.pumpState,
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
        #else
            telemetryLogger.debug("Skipping stored-credential authentication – JPake unavailable in this build")
        #endif
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

    func setPumpCommForTesting(_ pumpComm: PumpComm) {
        pumpComm.delegate = self
        tandemPump.pumpComm = pumpComm
    }

    func setActiveHistoryFetchSession(_ session: HistoryFetchSession?) {
        activeHistoryFetchSession.value = session
    }

    private enum ResponseSource {
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

    private func logger(for source: ResponseSource) -> TandemLogger {
        switch source {
        case .telemetry:
            return telemetryLogger
        case .notification:
            return notificationLogger
        }
    }

    private static func makeDefaultStatus() -> PumpManagerStatus {
        PumpManagerStatus(
            timeZone: TimeZone.current,
            device: HKDevice(
                name: "TandemPump",
                manufacturer: "Tandem",
                model: "Mobi",
                hardwareVersion: nil as String?,
                firmwareVersion: nil as String?,
                softwareVersion: nil as String?,
                localIdentifier: nil as String?,
                udiDeviceIdentifier: nil as String?
            ),
            pumpBatteryChargeRemaining: nil,
            basalDeliveryState: .active(Date()),
            bolusState: .noBolus,
            insulinType: nil,
            deliveryIsUncertain: false
        )
    }

    private static func makeStatus(from state: TandemPumpManagerState) -> PumpManagerStatus {
        var status = makeDefaultStatus()
        // TODO(jwoglom): add hardware/firmware/software versions from hardwareinforequest
        status.basalDeliveryState = state.basalDeliveryState ?? status.basalDeliveryState
        status.bolusState = state.bolusState
        status.deliveryIsUncertain = state.deliveryIsUncertain
        status.pumpBatteryChargeRemaining = state.lastBatteryReading?.chargeRemaining
        return status
    }

    public init(state: TandemPumpManagerState) {
        lockedState = Locked(state)
        lockedStatus = Locked(TandemPumpManager.makeStatus(from: state))
        lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        lockedReservoirValue = Locked(state.lastReservoirReading)
        tandemPump = TandemPump(pumpState: state.pumpState)
        needsSessionInitialization.value = state.pumpState?.valid == true

        tandemPump.delegate = self
        pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        tandemPump.configureDeliveryActions(enabled: state.insulinDeliveryActionsEnabled)
        tandemPump.configureConnectionSharing(enabled: state.connectionSharingEnabled)
        configureStateSuppliers()

        if case let .tempBasal(dose: dose) = state.basalDeliveryState {
            activeTempBasal.value = ActiveTempBasal(dose: dose, scheduledRate: dose.unitsPerHour)
        }
    }

    public required init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else {
            return nil
        }

        lockedState = Locked(state)
        lockedStatus = Locked(TandemPumpManager.makeStatus(from: state))
        lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        lockedReservoirValue = Locked(state.lastReservoirReading)
        tandemPump = TandemPump(pumpState: state.pumpState)
        needsSessionInitialization.value = state.pumpState?.valid == true

        tandemPump.delegate = self
        pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        tandemPump.configureDeliveryActions(enabled: state.insulinDeliveryActionsEnabled)
        tandemPump.configureConnectionSharing(enabled: state.connectionSharingEnabled)
        configureStateSuppliers()

        log.debug("Initialized TandemPumpManager: state=\(state)")

        if state.pumpState?.valid == true {
            // start connection
            tandemPump.startScanning()
        }

        if case let .tempBasal(dose: dose) = state.basalDeliveryState {
            activeTempBasal.value = ActiveTempBasal(dose: dose, scheduledRate: dose.unitsPerHour)
        }
    }

    public var rawState: RawStateValue {
        lockedState.value.rawValue
    }

    public var state: TandemPumpManagerState {
        lockedState.value
    }

    public var debugDescription: String {
        "TandemPumpManager(state: \(lockedState.value))"
    }

    // TODO(jwoglom): replace with connectedAndPaired?
    public var isOnboarded: Bool {
        lockedState.value.pumpState != nil
    }

    private var hasPairedPumpState: Bool {
        lockedState.value.pumpState?.valid == true
    }

    public var connectedAndPaired: Bool {
        guard let _ = transportLock.value else {
            return false
        }
        return hasPairedPumpState
    }

    public var pairedTransport: PumpMessageTransport? {
        guard let transport = transportLock.value,
              lockedState.value.pumpState?.valid == true,
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
        false // TODO(jwoglom): TBD
    }

    public var pumpReservoirCapacity: Double {
        250 // Tandem mobi reservoir capacity in units. t:slim X2 is 300
    }

    public var lastSync: Date? {
        lockedState.value.lastReconciliation
    }

    public var status: PumpManagerStatus {
        lockedStatus.value
    }

    public var pumpStatus: PumpManagerStatus {
        lockedStatus.value
    }

    public var pumpBatteryChargeRemaining: Double? {
        lockedBatteryChargeRemaining.value
    }

    public var reservoirLevel: ReservoirValue? {
        lockedReservoirValue.value
    }

    public var insulinDeliveryActionsEnabled: Bool {
        lockedState.value.insulinDeliveryActionsEnabled
    }

    public var connectionSharingEnabled: Bool {
        lockedState.value.connectionSharingEnabled
    }

    public var autoAcknowledgeBasalAlerts: Bool {
        lockedState.value.autoAcknowledgeBasalAlerts
    }

    private func handleBatteryResponse(_ response: CurrentBatteryAbstractResponse, source: ResponseSource) {
        let percent = Double(response.batteryPercent) / 100.0
        let timestamp = Date()
        lockedBatteryChargeRemaining.value = percent

        logger(for: source).debug("[\(source.label)] Battery updated: \(percent * 100)% remaining")

        updateStatus { status in
            status.pumpBatteryChargeRemaining = percent
        }

        var managerState = lockedState.value
        managerState.lastBatteryReading = TandemPumpManagerState.BatteryReading(date: timestamp, chargeRemaining: percent)
        lockedState.value = managerState

        notifyDelegateStateUpdated()
    }

    private func handleReservoirResponse(_ response: InsulinStatusResponse, source: ResponseSource) {
        // integer units
        let units = Double(response.currentInsulinAmount)
        let timestamp = Date()
        let reservoirValue = SimpleReservoirValue(startDate: timestamp, unitVolume: units)

        lockedReservoirValue.value = reservoirValue

        logger(for: source).debug("[\(source.label)] Reservoir updated: \(String(format: "%.2f", units)) U remaining")

        var managerState = lockedState.value
        managerState.lastReconciliation = timestamp
        managerState.lastReservoirReading = reservoirValue
        lockedState.value = managerState

        notifyDelegateOfReservoir(reservoirValue)
        notifyDelegateStateUpdated()
    }

    private func handleBasalResponse(_ response: CurrentBasalStatusResponse, source: ResponseSource) {
        let rateUnitsPerHour = Double(response.currentBasalRate) / 1000.0
        let profileUnitsPerHour = Double(response.profileBasalRate) / 1000.0
        let timestamp = Date()

        logger(for: source).debug("[\(source.label)] Basal updated: \(String(format: "%.3f", rateUnitsPerHour)) U/hr")

        let newBasalState: PumpManagerStatus.BasalDeliveryState
        if rateUnitsPerHour <= 0 {
            newBasalState = .suspended(timestamp)
        } else if let tempBasal = activeTempBasal.value {
            newBasalState = .tempBasal(tempBasal.dose)
        } else {
            newBasalState = .active(timestamp)
            activeTempBasal.value = nil
        }

        updateStatus { status in
            status.basalDeliveryState = newBasalState
        }

        var managerState = lockedState.value
        managerState.basalDeliveryState = newBasalState
        managerState.lastBasalStatusDate = timestamp
        managerState.currentBasalRate = rateUnitsPerHour
        managerState.lastBasalRateUpdate = timestamp
        lockedState.value = managerState

        notifyDelegateStateUpdated()
    }

    private func handleHomeScreenMirrorResponse(_ response: HomeScreenMirrorResponse, source _: ResponseSource) {
        let timestamp = Date()
        let newBasalState: PumpManagerStatus.BasalDeliveryState

        if response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.basal.rawValue ||
            response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.zeroBasal.rawValue ||
            response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.increaseBasal.rawValue ||
            response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.attenuatedBasal.rawValue
        {
            newBasalState = .active(timestamp)

        } else if response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.suspend.rawValue {
            newBasalState = .suspended(timestamp)
        } else if response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.tempRate.rawValue ||
            response.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.zeroTempRate.rawValue
        {
            // not updated here, instead see handleTempRateResponse
            return
        } else {
            // unknown state
            return
        }

        updateStatus { status in
            status.basalDeliveryState = newBasalState
        }

        var managerState = lockedState.value
        managerState.basalDeliveryState = newBasalState
        managerState.lastBasalStatusDate = timestamp
        managerState.basalStatusIcon = TandemPumpManagerState.HomeScreenBasalStatus(rawValue: response.basalStatusIconId)
        managerState.bolusStatusIcon = TandemPumpManagerState.HomeScreenBolusStatus(rawValue: response.bolusStatusIconId)
        managerState.cgmAlertIcon = TandemPumpManagerState.HomeScreenCGMAlert(rawValue: response.cgmAlertIconId)
        lockedState.value = managerState

        notifyDelegateStateUpdated()
    }

    private func handleControlIQResponse(_ response: ControlIQInfoV2Response, source: ResponseSource) {
        logger(for: source)
            .debug(
                "[\(source.label)] ControlIQ updated: enabled=\(response.closedLoopEnabled), mode=\(response.currentUserModeTypeRaw)"
            )

        var managerState = lockedState.value
        managerState.controlIQEnabled = response.closedLoopEnabled
        managerState.controlIQUserMode = TandemPumpManagerState.ControlIQUserMode(rawValue: response.currentUserModeTypeRaw)
        managerState.controlIQWeight = response.weight
        managerState.controlIQTotalDailyInsulin = response.totalDailyInsulin
        managerState.lastControlIQUpdate = Date()
        lockedState.value = managerState

        notifyDelegateStateUpdated()
    }

    private func handleTimeSinceResetResponse(_ response: TimeSinceResetResponse, source: ResponseSource) {
        let timeSinceReset = response.pumpTimeSinceReset

        logger(for: source).debug("[\(source.label)] TimeSinceReset updated: \(timeSinceReset)")

        var managerState = lockedState.value
        if var pumpState = managerState.pumpState {
            pumpState.timeSinceReset = timeSinceReset
            managerState.pumpState = pumpState
            lockedState.value = managerState
            pumpComm.syncPumpState(pumpState)
            needsSessionInitialization.value = false

            // Update the PumpStateSupplier with the new value
            updatePairingArtifacts(with: pumpState)

            notifyDelegateStateUpdated()
        }
    }

    private func handleBolusResponse(_ response: CurrentBolusStatusResponse, source: ResponseSource) {
        logger(for: source)
            .debug(
                "[\(source.label)] Bolus updated - status: \(response.status) id: \(response.bolusId)"
            )


        // Normal CurrentBolusStatus fetch
        if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            return
        }

        guard let progressReport = bolusProgressReport else {
            return
        }

        if response.status == .delivering {
            if status.bolusState == .initiating, let bolusState = activeBolus.value {
                updateStatus { status in
                    status.bolusState = .inProgress(bolusState.dose.toDoseEntry(endDate: nil))
                }
            }
            
            progressReport.notify()
            return
        }

        if response.bolusId == 0, progressReport.bolusStatedOn != nil {
            // Bolus is finished
            telemetryScheduler.cancelAll()

            updateStatus { status in
                status.bolusState = .noBolus
            }

            var events = [progressReport.getPumpEvent()]
            bolusProgressReport = nil
            
            if let tempBasal = self.activeTempBasal.value {
                events.append(
                    NewPumpEvent.tempBasal(dose: tempBasal.dose, date: tempBasal.dose.startDate)
                )
            }

            recordReconciliation(at: Date.now)

            pumpDelegate.notify { delegate in
                guard let delegate = delegate else { return }
                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: events,
                    lastReconciliation: self.lockedState.value.lastReconciliation,
                    replacePendingEvents: true,
                    completion: { _ in }
                )
            }
        }
    }

    private func handleTempRateResponse(_ response: TempRateResponse, source: ResponseSource) {
        let timestamp = Date()

        logger(for: source)
            .debug(
                "[\(source.label)] TempRate updated: active=\(response.active) percent=\(response.percentage) duration=\(response.duration)min startTime=\(response.startTime)"
            )

        if response.active {
            // Get the scheduled basal rate to calculate actual temp rate
            let scheduledRate = getScheduledBasalRate()
            let tempRateUnitsPerHour = scheduledRate * Double(response.percentage) / 100.0

            let syncIdentifier = activeTempBasal.value?.dose.syncIdentifier
                ?? "temp-\(Int(response.startTime.timeIntervalSince1970))"

            let dose = DoseEntry.tempBasal(
                absoluteUnit: tempRateUnitsPerHour,
                duration: TimeInterval(seconds: Double(response.duration)),
                insulinType: lockedState.value.insulinType,
                startDate: response.startTime,
                syncIdentifier: syncIdentifier
            )

            activeTempBasal.value = ActiveTempBasal(dose: dose, scheduledRate: scheduledRate)

            updateStatus { status in
                status.basalDeliveryState = .tempBasal(dose)
            }

            var managerState = lockedState.value
            managerState.basalDeliveryState = .tempBasal(dose)
            managerState.lastBasalStatusDate = timestamp
            managerState.tempRateActive = true
            managerState.tempRatePercentage = response.percentage
            managerState.tempRateDuration = response.duration
            managerState.lastTempRateUpdate = timestamp
            lockedState.value = managerState
        } else {
            // No temp basal active - clear tracking
            activeTempBasal.value = nil

            // Clear temp rate state
            var managerState = lockedState.value
            managerState.tempRateActive = false
            managerState.tempRatePercentage = nil
            managerState.tempRateDuration = nil
            managerState.lastTempRateUpdate = timestamp
            lockedState.value = managerState

            // Don't update basalDeliveryState here - let handleBasalResponse do it
            // This avoids a race where we clear temp basal but haven't gotten current basal status yet
            logger(for: source).debug("[\(source.label)] TempRate inactive - clearing activeTempBasal tracking")
        }

        notifyDelegateStateUpdated()
    }

    private func makeBatteryRequest() -> Message {
        let apiVersion = PumpStateSupplier.currentPumpApiVersion() ?? KnownApiVersion.apiV2_1.value
        return CurrentBatteryRequestBuilder.create(apiVersion: apiVersion)
    }

    private func fetchBatteryStatus() {
        guard let transport = telemetryTransportIfReady(for: .battery) else {
            telemetryLogger.error("Transport not available for battery telemetry")
            return
        }

        do {
            let request = makeBatteryRequest()

            if let v2Request = request as? CurrentBatteryV2Request {
                let response: CurrentBatteryV2Response = try pumpComm.sendMessage(
                    transport: transport,
                    message: v2Request,
                    expecting: CurrentBatteryV2Response.self
                )

                handleBatteryResponse(response, source: .telemetry)
            } else if let v1Request = request as? CurrentBatteryV1Request {
                let response: CurrentBatteryV1Response = try pumpComm.sendMessage(
                    transport: transport,
                    message: v1Request,
                    expecting: CurrentBatteryV1Response.self
                )

                handleBatteryResponse(response, source: .telemetry)
            } else {
                telemetryLogger
                    .error(
                        "Battery telemetry request builder returned unsupported type: \(String(describing: type(of: request)))"
                    )
            }
        } catch {
            telemetryLogger.error("Battery telemetry request failed: \(error)")
        }
    }

    private func fetchReservoirStatus() {
        guard let transport = telemetryTransportIfReady(for: .reservoir) else {
            telemetryLogger.error("Transport not available for reservoir telemetry")
            return
        }

        do {
            let response = try pumpComm.sendMessage(
                transport: transport,
                message: InsulinStatusRequest(),
                expecting: InsulinStatusResponse.self
            )

            handleReservoirResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("Reservoir telemetry request failed: \(error)")
        }
    }

    private func fetchBasalStatus() {
        guard let transport = telemetryTransportIfReady(for: .basal) else {
            telemetryLogger.error("Transport not available for basal telemetry")
            return
        }

        do {
            telemetryLogger.debug("Requesting message fetchBasalStatus")

            // First check if a temp basal is active
            let tempRateResponse: TempRateResponse = try pumpComm.sendMessage(
                transport: transport,
                message: TempRateRequest(),
                expecting: TempRateResponse.self
            )

            handleTempRateResponse(tempRateResponse, source: .telemetry)

            // If no temp basal is active, get current basal rate to ensure we're showing scheduled
            if !tempRateResponse.active {
                let basalResponse = try pumpComm.sendMessage(
                    transport: transport,
                    message: CurrentBasalStatusRequest(),
                    expecting: CurrentBasalStatusResponse.self
                )

                handleBasalResponse(basalResponse, source: .telemetry)
            }
        } catch {
            telemetryLogger.error("Basal telemetry request failed: \(error)")
        }
    }

    func fetchBolusStatus() {
        guard let transport = telemetryTransportIfReady(for: .bolus) else {
            return
        }

        do {
            let response: CurrentBolusStatusResponse = try pumpComm.sendMessage(
                transport: transport,
                message: CurrentBolusStatusRequest(),
                expecting: CurrentBolusStatusResponse.self
            )

            handleBolusResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("Bolus telemetry request failed: \(error)")
        }
    }

    private func fetchTimeSinceReset() {
        guard let transport = telemetryTransportIfReady(for: .timeSinceReset) else {
            return
        }

        do {
            let response: TimeSinceResetResponse = try pumpComm.sendMessage(
                transport: transport,
                message: TimeSinceResetRequest(),
                expecting: TimeSinceResetResponse.self
            )

            handleTimeSinceResetResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("TimeSinceReset telemetry request failed: \(error)")
        }
    }

    private func fetchTempRateStatus() {
        guard let transport = telemetryTransportIfReady(for: .basal) else {
            return
        }

        do {
            let response: TempRateResponse = try pumpComm.sendMessage(
                transport: transport,
                message: TempRateRequest(),
                expecting: TempRateResponse.self
            )

            handleTempRateResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("TempRate telemetry request failed: \(error)")
        }
    }

    private func fetchAlertAndAlarmStatus() {
        guard let transport = telemetryTransportIfReady(for: .alerts) else {
            return
        }

        // Fetch alert status
        do {
            let alertResponse: AlertStatusResponse = try pumpComm.sendMessage(
                transport: transport,
                message: AlertStatusRequest(),
                expecting: AlertStatusResponse.self
            )

            telemetryLogger.debug("[telemetry] Alert status: \(alertResponse.alerts)")

            // Auto-acknowledge basal alerts if enabled
            if lockedState.value.autoAcknowledgeBasalAlerts {
                autoAcknowledgeBasalAlertsIfNeeded(alertResponse: alertResponse, transport: transport)
            }
        } catch {
            telemetryLogger.error("Alert status telemetry request failed: \(error)")
        }

        // Fetch alarm status (no auto-ack for alarms)
        do {
            let alarmResponse: AlarmStatusResponse = try pumpComm.sendMessage(
                transport: transport,
                message: AlarmStatusRequest(),
                expecting: AlarmStatusResponse.self
            )

            telemetryLogger.debug("[telemetry] Alarm status: \(alarmResponse.alarms)")
        } catch {
            telemetryLogger.error("Alarm status telemetry request failed: \(error)")
        }
    }

    private func fetchControlIQStatus() {
        guard let transport = telemetryTransportIfReady(for: .controlIQ) else {
            return
        }

        do {
            let response: ControlIQInfoV2Response = try pumpComm.sendMessage(
                transport: transport,
                message: ControlIQInfoV2Request(),
                expecting: ControlIQInfoV2Response.self
            )

            handleControlIQResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("ControlIQ status telemetry request failed: \(error)")
        }
    }

    private func fetchHomeScreenStatus() {
        guard let transport = telemetryTransportIfReady(for: .homeScreen) else {
            return
        }

        do {
            let response: HomeScreenMirrorResponse = try pumpComm.sendMessage(
                transport: transport,
                message: HomeScreenMirrorRequest(),
                expecting: HomeScreenMirrorResponse.self
            )

            handleHomeScreenMirrorResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("HomeScreen telemetry request failed: \(error)")
        }
    }

    private func fetchNotificationCount() {
        guard let transport = telemetryTransportIfReady(for: .notifications) else {
            return
        }

        let bundle = NotificationBundle()
        for request in NotificationBundle.allRequests() {
            if let response = try? pumpComm.sendMessage(transport: transport, message: request),
               NotificationBundle.isNotificationResponse(response)
            {
                bundle.add(response)
            }
        }

        var managerState = lockedState.value
        managerState.notificationCount = bundle.getNotificationCount()
        managerState.lastNotificationUpdate = Date()
        lockedState.value = managerState

        notifyDelegateStateUpdated()
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

    private func notifyDelegateStateUpdated() {
        guard let delegate = pumpManagerDelegate else { return }
        pumpDelegate.queue.async { [weak self] in
            guard let self = self else { return }
            delegate.pumpManagerDidUpdateState(self)
        }
    }

    private func resolvedStartSequence(after startDate: Date?) -> UInt32? {
        if let lastSequence = lockedState.value.lastHistorySequenceNum {
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

    private func applyClockChanges(from logs: [HistoryLog]) {
        logs.forEach { log in
            switch log {
            case let clockChange as DateChangeHistoryLog:
                let delta = Int(clockChange.dateAfter) - Int(clockChange.datePrior)
                historyTimestampReconciler.recordClockChange(at: clockChange.sequenceNum, deltaSec: delta)
            case let clockChange as TimeChangedHistoryLog:
                let delta = Int(clockChange.timeAfter) - Int(clockChange.timePrior)
                historyTimestampReconciler.recordClockChange(at: clockChange.sequenceNum, deltaSec: delta)
            default:
                break
            }
        }
    }

    private func notifyDelegateOfReservoir(_ value: ReservoirValue) {
        guard let delegate = pumpManagerDelegate else { return }
        pumpDelegate.queue.async { [weak self] in
            guard let self = self else { return }
            delegate.pumpManager(self, didReadReservoirValue: value.unitVolume, at: value.startDate) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.telemetryLogger.debug("Delegate accepted reservoir update")
                case let .failure(error):
                    self.telemetryLogger.warning("Delegate failed to store reservoir update: \(error)")
                }
            }
        }
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

    private func updateStatus(_ update: (inout PumpManagerStatus) -> Void) {
        let oldStatus = lockedStatus.value
        var newStatus = oldStatus
        update(&newStatus)
        lockedStatus.value = newStatus

        var managerState = lockedState.value
        managerState.basalDeliveryState = newStatus.basalDeliveryState
        managerState.bolusState = newStatus.bolusState
        managerState.deliveryIsUncertain = newStatus.deliveryIsUncertain
        lockedState.value = managerState

        notifyStatusObservers(oldStatus: oldStatus, newStatus: newStatus)
    }

    private func notifyPumpManagerDelegateOfError(_ error: PumpCommError) {
        guard let delegate = pumpManagerDelegate, let queue = delegateQueue else { return }
        queue.async {
            delegate.pumpManager(self, didError: PumpManagerError.communication(error))
        }
    }

    private func recordReconciliation(at date: Date) {
        var state = lockedState.value
        state.lastReconciliation = date
        lockedState.value = state
        notifyPumpManagerDelegateDidUpdateState()
    }

    func notifyPumpManagerDelegateDidUpdateState() {
        guard let delegate = pumpManagerDelegate, let queue = delegateQueue else { return }
        queue.async {
            delegate.pumpManagerDidUpdateState(self)
        }
    }

    private func completeBolus(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerError?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            switch result {
            case let .success(dose):
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }
                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: dose.programmedUnits, date: dose.startDate)],
                        lastReconciliation: self.lockedState.value.lastReconciliation,
                        replacePendingEvents: false, // Do not replace pending events while bolus is running
                        completion: { _ in }
                    )
                }

                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    private func completeCancelBolus(
        _ result: PumpManagerResult<DoseEntry?>,
        completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void
    ) {
        guard let queue = delegateQueue else { return }
        queue.async {
            if case let .success(dose) = result, let dose = dose {
                var events = [
                    NewPumpEvent.bolus(dose: dose, units: dose.deliveredUnits ?? 0, date: dose.startDate)
                ]

                if let tempBasal = self.activeTempBasal.value {
                    events.append(
                        NewPumpEvent.tempBasal(dose: tempBasal.dose, date: tempBasal.dose.startDate)
                    )
                }

                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }
                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: events,
                        lastReconciliation: self.lockedState.value.lastReconciliation,
                        replacePendingEvents: true,
                        completion: { _ in }
                    )
                }
            }

            completion(result)
        }
    }

    private func completeTempBasal(
        _ result: PumpManagerResult<[NewPumpEvent]>,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        guard let queue = delegateQueue else { return }

        queue.async {
            switch result {
            case let .success(events):
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }
                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: events,
                        lastReconciliation: self.lockedState.value.lastReconciliation,
                        replacePendingEvents: true,
                        completion: { _ in }
                    )
                }

                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    private func completeSuspend(_ result: (Error?, [NewPumpEvent]), completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            if result.0 == nil, !result.1.isEmpty {
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }

                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: result.1,
                        lastReconciliation: self.lockedState.value.lastReconciliation,
                        replacePendingEvents: true,
                        completion: { _ in }
                    )
                }
            }

            completion(result.0)
        }
    }

    private func completeResume(_ result: (Error?, [NewPumpEvent]), completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            if result.0 == nil, !result.1.isEmpty {
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }

                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: result.1,
                        lastReconciliation: self.lockedState.value.lastReconciliation,
                        replacePendingEvents: true,
                        completion: { _ in }
                    )
                }
            }

            completion(result.0)
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
            updateStatus { status in
                status.deliveryIsUncertain = false
            }
            return
        }

        guard isOnboarded else {
            log.error("connect() requested before pump is paired")
            notifyPumpManagerDelegateOfError(.missingAuthenticationKey)
            return
        }

        updateStatus { status in
            status.deliveryIsUncertain = true
        }

        tandemPump.startScanning()
    }

    public func disconnect() {
        if let manager = activePeripheralManager {
            notificationRouter.stop(with: manager)
            activePeripheralManager = nil
        }
        pumpComm.manager = nil
        updateTransport(nil)
        tandemPump.disconnect()
    }

    public func configureDeliveryActions(_ enabled: Bool) {
        tandemPump.configureDeliveryActions(enabled: enabled)

        var state = lockedState.value
        guard state.insulinDeliveryActionsEnabled != enabled else { return }
        state.insulinDeliveryActionsEnabled = enabled
        lockedState.value = state

        notifyDelegateStateUpdated()
    }

    public func configureConnectionSharing(_ enabled: Bool) {
        tandemPump.configureConnectionSharing(enabled: enabled)

        var state = lockedState.value
        guard state.connectionSharingEnabled != enabled else { return }
        state.connectionSharingEnabled = enabled
        lockedState.value = state

        notifyDelegateStateUpdated()
    }

    public func configureAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        var state = lockedState.value
        guard state.autoAcknowledgeBasalAlerts != enabled else { return }
        state.autoAcknowledgeBasalAlerts = enabled
        lockedState.value = state

        telemetryLogger.info("Auto-acknowledge basal alerts \(enabled ? "enabled" : "disabled")")
        notifyDelegateStateUpdated()
    }

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        if !telemetryConfigured {
            telemetryScheduler.schedule(kind: .history, interval: historyTelemetryInterval, leeway: 10.0) { [weak self] in
                self?.performScheduledHistoryFetch()
            }
            telemetryConfigured = true
        }

        fetchBasalStatus()
        fetchReservoirStatus()
        fetchBatteryStatus()
        fetchBolusStatus()
        fetchHomeScreenStatus()
        fetchControlIQStatus()
        fetchNotificationCount()

        recordReconciliation(at: Date.now)

        completion?(lockedState.value.lastReconciliation)
    }

    // MARK: - History Fetching

    public func fetchPumpHistory(since startDate: Date? = nil, completion: @escaping (Error?) -> Void) {
        guard let transport = transportLock.value else {
            completion(PumpManagerError.connection(nil))
            return
        }

        historyFetchQueue.async { [weak self] in
            guard let self else { return }

            let session = HistoryFetchSession(
                transport: transport,
                pumpComm: self.pumpComm,
                startSequence: self.resolvedStartSequence(after: startDate),
                maxEntries: 500
            )

            self.activeHistoryFetchSession.value = session

            do {
                let logs = try session.fetchWithRetry()
                self.activeHistoryFetchSession.value = nil

                let unseen = self.historyDeduplicator.filterUnseen(logs)
                self.applyClockChanges(from: unseen)

                let events = self.historyMapper.mapToEvents(
                    unseen,
                    reconciler: self.historyTimestampReconciler,
                    insulinType: self.lockedState.value.insulinType,
                    timeZone: self.lockedStatus.value.timeZone
                )

                let (reconciledEvents, stillPending, _) = self.historyReconciler.reconcile(
                    pendingDoses: self.lockedState.value.pendingDoses,
                    historyEvents: events
                )

                var updatedState = self.lockedState.value
                updatedState.pendingDoses = stillPending
                updatedState.lastHistoryReconciliation = Date()
                if let lastLog = unseen.last {
                    updatedState.lastHistorySequenceNum = lastLog.sequenceNum
                }
                self.lockedState.value = updatedState

                self.notifyPumpManagerDelegateDidUpdateState()

                guard let delegate = self.pumpManagerDelegate, let queue = self.delegateQueue else {
                    completion(nil)
                    return
                }

                queue.async {
                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: reconciledEvents,
                        lastReconciliation: updatedState.lastHistoryReconciliation,
                        replacePendingEvents: true,
                        completion: completion
                    )
                }
            } catch {
                self.activeHistoryFetchSession.value = nil
                completion(error)
            }
        }
    }

    public func sendMessage(message: Message) -> Message? {
        guard let transport = pairedTransport else {
            return nil
        }
        return try? transport.sendMessage(message)
    }

    public func setMustProvideBLEHeartbeat(_: Bool) {
        // Store this setting to control heartbeat behavior
        // The actual heartbeat logic will be implemented in future pump communication
    }

    public func createBolusProgressReporter(reportingOn _: DispatchQueue) -> DoseProgressReporter? {
        bolusProgressReport
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        // Tandem pumps typically deliver at up to 1 unit every 5 seconds.
        // Use a conservative estimate of 30 seconds per unit for now.
        max(units, 0) * 30.0
    }

    public func setTargetPeripheral(_ peripheralIdentifier: UUID?) {
        targetPeripheralIdentifier = peripheralIdentifier
    }

    public func setScanningMode(_ enabled: Bool) {
        inScanningMode.value = enabled
    }

    private func handleUnsolicitedHistoryStream(_ response: HistoryLogStreamResponse) {
        historyFetchQueue.async { [weak self] in
            guard let self else { return }

            let unseen = self.historyDeduplicator.filterUnseen(response.historyLogs)
            guard !unseen.isEmpty else {
                self.telemetryLogger.debug(
                    "[history] Ignoring unsolicited streamId=\(response.streamId) with no new entries"
                )
                return
            }

            self.applyClockChanges(from: unseen)

            let events = self.historyMapper.mapToEvents(
                unseen,
                reconciler: self.historyTimestampReconciler,
                insulinType: self.lockedState.value.insulinType,
                timeZone: self.lockedStatus.value.timeZone
            )

            let (reconciledEvents, stillPending, _) = self.historyReconciler.reconcile(
                pendingDoses: self.lockedState.value.pendingDoses,
                historyEvents: events
            )

            var updatedState = self.lockedState.value
            updatedState.pendingDoses = stillPending
            updatedState.lastHistoryReconciliation = Date()
            if let maxSequence = unseen.map(\.sequenceNum).max() {
                updatedState.lastHistorySequenceNum = maxSequence
            }
            self.lockedState.value = updatedState

            self.notifyPumpManagerDelegateDidUpdateState()

            guard let delegate = self.pumpManagerDelegate, let queue = self.delegateQueue else {
                return
            }

            queue.async {
                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: reconciledEvents,
                    lastReconciliation: updatedState.lastHistoryReconciliation,
                    replacePendingEvents: true,
                    completion: { _ in }
                )
            }
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

        Task {
            do {
                let peripheralUuid = peripheral.identifier.uuidString
                let sanitizedCode = try PumpStateSupplier.sanitizeAndStorePairingCode(pairingCode)
                tandemPump.startScanning()

                var tries = 0
                while peripheral.state != .connected {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    log.debug("Waiting for peripheral to be in connected state, in \(peripheral.state): \(peripheral)")
                    tries += 1

                    if tries >= 50 {
                        completion(.failure(NSError(
                            domain: "TandemPumpManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Gave up waiting for peripheral to connect"]
                        )))
                        return
                    }
                }

                // Also wait for transport to be initialized (didCompleteConfiguration must have been called)
                tries = 0
                while transportLock.value == nil {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    log.debug("Waiting for transport to be initialized...")
                    tries += 1

                    if tries >= 50 {
                        completion(.failure(NSError(
                            domain: "TandemPumpManager",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Gave up waiting for transport initialization"]
                        )))
                        return
                    }
                }

                guard let transport = transportLock.value else {
                    completion(.failure(PumpCommError.pumpNotConnected))
                    return
                }

                #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                    DispatchQueue.global(qos: .userInitiated).async { [pumpComm, weak self] in
                        do {
                            // pair() now handles: JPAKE + 250ms wait + TimeSinceResetRequest
                            try pumpComm.pair(transport: transport, peripheralUuid: peripheralUuid, pairingCode: sanitizedCode)

                            // After successful pairing and session initialization, trigger initial telemetry refresh
                            DispatchQueue.main.async {
                                self?.telemetryLogger.debug("Pairing complete – triggering initial telemetry refresh")
                                self?.ensureCurrentPumpData { _ in }
                            }

                            completion(.success(()))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                #else
                    completion(.failure(PumpCommError.pumpChallengeError))
                #endif
            } catch {
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
        guard let transport = pairedTransport else {
            telemetryLogger.error("[enactBolus] could not enact bolus because no paired transport")
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeBolus(.failure(.communication(error)), completion: completion)
            return
        }

        if let error = validateBolusRequest(units: units, activationType) {
            telemetryLogger
                .error("[enactBolus] could not validate bolus request: units=\(units) activationType=\(activationType)")
            completeBolus(.failure(error), completion: completion)
            return
        }

        updateStatus { status in
            status.bolusState = .initiating
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var permissionBolusId: UInt32?
            var shouldReleasePermissionOnFailure = false

            do {
                let permissionResponse: BolusPermissionResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: BolusPermissionRequest(),
                    expecting: BolusPermissionResponse.self
                )

                guard permissionResponse.isPermissionGranted else {
                    throw PumpCommError.errorResponse(response: permissionResponse)
                }

                permissionBolusId = UInt32(clamping: permissionResponse.bolusId)
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

                telemetryLogger.info("[enactBolus] sending InitiateBolusRequest=\(bolusRequest)")

                let initiateResponse: InitiateBolusResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: bolusRequest,
                    expecting: InitiateBolusResponse.self
                )

                guard initiateResponse.wasBolusInitiated else {
                    telemetryLogger.info("[enactBolus] bolus not initiated")
                    throw PumpCommError.errorResponse(response: initiateResponse)
                }

                telemetryLogger.info("[enactBolus] bolus started")

                let dose = UnfinalizedDose(
                    units: units,
                    duration: getBolusDuration(units),
                    activationType: activationType,
                    insulinType: lockedState.value.insulinType
                )

                let syncId = HistoryToDoseMapper.bolusSyncIdentifier(Int(initiateResponse.bolusId))
                let doseEntry = dose.toDoseEntry(endDate: nil, syncIdentifier: syncId)

                bolusProgressReport = TandemDoseProgressReporter(dose: doseEntry, activationType: activationType)
                telemetryScheduler.schedule(kind: .bolus, interval: .seconds(1), leeway: .seconds(0.5), handler: fetchBolusStatus)

                shouldReleasePermissionOnFailure = false

                self.activeBolus.value = ActiveBolus(
                    id: initiateResponse.bolusId,
                    dose: dose
                )

                self.updateStatus { status in
                    status.bolusState = .initiating
                }

                self.recordReconciliation(at: Date.now)
                self.completeBolus(.success(doseEntry), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                if shouldReleasePermissionOnFailure, let bolusId = permissionBolusId {
                    self.releaseBolusPermission(transport: transport, bolusId: bolusId)
                }
                self.activeBolus.value = nil
                self.updateStatus { status in
                    status.bolusState = .noBolus
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeBolus(.failure(.communication(pumpError)), completion: completion)
            }
        }
    }

    private func getBolusDuration(_ units: Double) -> TimeInterval {
        if units <= 10 {
            // < 10 units == 0.15u/s
            return TimeInterval(units / 0.15)
        }

        // <10 units == 0.15u/s & => 10units == 0.075u/s
        return TimeInterval(10 / 0.15) + TimeInterval((units - 10) / 0.075)
    }

    public func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void) {
        updateStatus { status in
            status.bolusState = .canceling
        }

        guard let transport = pairedTransport else {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeCancelBolus(.failure(.communication(error)), completion: completion)
            return
        }

        guard let active = activeBolus.value else {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            let error = PumpCommError.noActiveBolus
            notifyPumpManagerDelegateOfError(error)
            completeCancelBolus(.failure(.communication(error)), completion: completion)
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
                    throw PumpCommError.errorResponse(response: response)
                }

                self.updateStatus { status in
                    status.bolusState = .noBolus
                }

                let canceledDose = self.activeBolus.value?.dose.toDoseEntry(endDate: Date.now)

                self.recordReconciliation(at: Date.now)
                self.completeCancelBolus(.success(canceledDose), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.bolusState = .inProgress(active.dose.toDoseEntry(endDate: nil))
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeCancelBolus(.failure(.communication(pumpError)), completion: completion)
            }
        }
    }

    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (_ error: PumpManagerError?) -> Void
    ) {
        guard let transport = pairedTransport else {
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeTempBasal(.failure(.communication(error)), completion: completion)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var pumpEvents: [NewPumpEvent] = []
            do {
                // First cancel running temp basal before starting a new one
                if let activeTempBasal = self.activeTempBasal.value {
                    updateStatus { status in
                        status.basalDeliveryState = .cancelingTempBasal
                    }

                    log.info("Cancelling temp basal...")
                    let response: StopTempRateResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: StopTempRateRequest(),
                        expecting: StopTempRateResponse.self
                    )

                    guard response.isStatusOK else {
                        log.error("Failed to cancel temp basal - status: \(response.status)")
                        throw PumpCommError.errorResponse(response: response)
                    }

                    let cancelledDose = DoseEntry.tempBasal(
                        absoluteUnit: activeTempBasal.scheduledRate,
                        duration: 0, // Ignored when a dose is finished
                        insulinType: lockedState.value.insulinType,
                        startDate: activeTempBasal.dose.startDate,
                        endDate: Date.now,
                        syncIdentifier: activeTempBasal.dose.syncIdentifier
                    )
                    pumpEvents.append(NewPumpEvent.tempBasal(dose: cancelledDose, date: cancelledDose.startDate))

                    self.updateStatus { status in
                        status.basalDeliveryState = .active(Date.now)
                    }
                }

                if duration <= 0 {
                    // Loop wants us to only cancel the temp basal
                    let basalDose = DoseEntry.basal(
                        rate: getScheduledBasalRate(),
                        insulinType: lockedState.value.insulinType
                    )
                    pumpEvents.append(NewPumpEvent.basal(dose: basalDose, date: basalDose.startDate))

                    self.activeTempBasal.value = nil

                    self.recordReconciliation(at: Date.now)
                    self.completeTempBasal(.success(pumpEvents), completion: completion)
                } else {
                    // Enact new temp basal
                    updateStatus { status in
                        status.basalDeliveryState = .initiatingTempBasal
                    }

                    let baselineRate = getScheduledBasalRate()
                    guard baselineRate > 0 else {
                        log.error("No current basal rate available...")
                        throw PumpCommError.other
                    }

                    let minutes = max(1, Int((duration / 60.0).rounded()))
                    let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)

                    // If percent is exactly 100%, don't send a temp basal - just return to scheduled basal
                    if percent == 100 {
                        log
                            .info(
                                "Requested temp basal is 100% (\(unitsPerHour)U/hr equals scheduled rate) - returning to scheduled basal instead"
                            )
                        let basalDose = DoseEntry.basal(
                            rate: baselineRate,
                            insulinType: lockedState.value.insulinType
                        )
                        pumpEvents.append(NewPumpEvent.basal(dose: basalDose, date: basalDose.startDate))

                        self.activeTempBasal.value = nil

                        self.updateStatus { status in
                            status.basalDeliveryState = .active(Date.now)
                        }

                        self.recordReconciliation(at: Date.now)
                        self.completeTempBasal(.success(pumpEvents), completion: completion)
                        return
                    }

                    log.info("Enact temp basal - units: \(unitsPerHour)U/hr, minutes: \(minutes), percent: \(percent)%")
                    let request = SetTempRateRequest(minutes: minutes, percent: percent)
                    let response: SetTempRateResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: request,
                        expecting: SetTempRateResponse.self
                    )

                    guard response.isStatusOK else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    let dose = DoseEntry.tempBasal(
                        absoluteUnit: baselineRate * (Double(percent) / 100),
                        duration: duration,
                        insulinType: lockedState.value.insulinType,
                        startDate: Date.now,
                        syncIdentifier: HistoryToDoseMapper.tempBasalSyncIdentifier(response.tempRateId)
                    )
                    pumpEvents.append(NewPumpEvent.tempBasal(dose: dose, date: dose.startDate))

                    self.activeTempBasal.value = ActiveTempBasal(dose: dose, scheduledRate: baselineRate)

                    self.recordReconciliation(at: Date.now)
                    self.completeTempBasal(.success(pumpEvents), completion: completion)
                }
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)

                if !pumpEvents.isEmpty {
                    // Ensure all events are commited to Loopkit
                    self.pumpDelegate.notify { delegate in
                        guard let delegate = delegate else { return }
                        delegate.pumpManager(
                            self,
                            hasNewPumpEvents: pumpEvents,
                            lastReconciliation: self.lockedState.value.lastReconciliation,
                            replacePendingEvents: true,
                            completion: { _ in }
                        )
                    }
                }

                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeTempBasal(.failure(.communication(pumpError)), completion: completion)
            }
        }
    }

    private var currentSettings: TandemPumpManagerSettings {
        lockedState.value.settings
    }

    private var latestInsulinOnBoard: Double? {
        lockedState.value.latestInsulinOnBoard
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
        let previousStatus = lockedStatus.value
        updateStatus { status in
            status.basalDeliveryState = .suspending
        }

        guard let transport = pairedTransport else {
            updateStatus { status in
                status.basalDeliveryState = previousStatus.basalDeliveryState
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeSuspend((error, []), completion: completion)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let response: SuspendPumpingResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: SuspendPumpingRequest(),
                    expecting: SuspendPumpingResponse.self
                )

                guard response.status == 0 else {
                    throw PumpCommError.errorResponse(response: response)
                }

                var doses = [
                    NewPumpEvent.suspend(dose: DoseEntry.suspend(suspendDate: Date.now))
                ]

                if let tempBasal = self.activeTempBasal.value {
                    let tempBasalDose = DoseEntry.tempBasal(
                        absoluteUnit: tempBasal.dose.unitsPerHour,
                        duration: 0,
                        insulinType: lockedState.value.insulinType,
                        startDate: tempBasal.dose.startDate,
                        endDate: Date.now,
                        syncIdentifier: tempBasal.dose.syncIdentifier
                    )
                    doses.append(
                        NewPumpEvent.tempBasal(dose: tempBasalDose, date: tempBasalDose.startDate)
                    )
                    self.activeTempBasal.value = nil
                }

                self.updateStatus { status in
                    status.basalDeliveryState = .suspended(Date.now)
                    status.bolusState = .noBolus
                }

                self.recordReconciliation(at: Date.now)
                self.completeSuspend((nil, doses), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeSuspend((pumpError, []), completion: completion)
            }
        }
    }

    public func resumeDelivery(completion: @escaping (_ error: Error?) -> Void) {
        let previousStatus = lockedStatus.value
        updateStatus { status in
            status.basalDeliveryState = .resuming
        }

        guard let transport = pairedTransport else {
            updateStatus { status in
                status.basalDeliveryState = previousStatus.basalDeliveryState
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeResume((error, []), completion: completion)
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
                    throw PumpCommError.errorResponse(response: response)
                }

                let events = [
                    NewPumpEvent.resume(dose: DoseEntry.resume(insulinType: lockedState.value.insulinType)),
                    NewPumpEvent
                        .basal(
                            dose: DoseEntry
                                .basal(rate: getScheduledBasalRate(), insulinType: lockedState.value.insulinType)
                        )
                ]
                self.activeTempBasal.value = nil
                self.updateStatus { status in
                    status.basalDeliveryState = .active(Date.now)
                }

                self.recordReconciliation(at: Date.now)
                self.completeResume((nil, events), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeResume((pumpError, []), completion: completion)
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
            delegateQueue.async {
                completion(.failure(PumpManagerError.communication(error)))
            }
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
                    for message in messages {
                        let response = try self.pumpComm.sendMessage(
                            transport: transport,
                            message: message
                        )
                        idpManager.processMessage(response)
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
                        throw PumpCommError.errorResponse(response: response)
                    }
                }

                // Step 7: Update local state
                let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: self.lockedStatus.value.timeZone)

                var managerState = self.lockedState.value
                managerState.basalRateSchedule = schedule
                managerState.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
                self.lockedState.value = managerState

                self.notifyDelegateStateUpdated()

                if let schedule = schedule {
                    self.delegateQueue.async {
                        completion(.success(schedule))
                    }
                } else {
                    self.delegateQueue.async {
                        completion(
                            .failure(
                                PumpManagerError.communication(
                                    PumpCommError.requestConstructionFailed(reason: "Basal schedule serialization failed")
                                )
                            )
                        )
                    }
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
                let hkUnit = HKUnit.internationalUnit().unitDivided(by: .hour())
                var appliedLimits = DeliveryLimits(maximumBasalRate: nil, maximumBolus: nil)

                if let maxBasal = deliveryLimits.maximumBasalRate?.doubleValue(for: hkUnit) {
                    let milliunits = Int((maxBasal * 1000.0).rounded())
                    let response: SetMaxBasalLimitResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits),
                        expecting: SetMaxBasalLimitResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    appliedLimits.maximumBasalRate = HKQuantity.init(unit: hkUnit, doubleValue: maxBasal)
                }

                if let maxBolus = deliveryLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit()) {
                    let milliunits = Int((maxBolus * 1000.0).rounded())
                    let response: SetMaxBolusLimitResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits),
                        expecting: SetMaxBolusLimitResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    appliedLimits.maximumBolus = HKQuantity.init(unit: HKUnit.internationalUnit(), doubleValue: maxBolus)
                }

                var managerState = self.lockedState.value
                managerState.settings.maxTempBasalRate = appliedLimits.maximumBasalRate?.doubleValue(for: hkUnit)
                managerState.settings.maxBolus = appliedLimits.maximumBolus?.doubleValue(for: HKUnit.internationalUnit())
                self.lockedState.value = managerState

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

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        telemetryLogger.debug("Preparing for pump deactivation – tearing down transport")
        disconnect()
        tandemPump.stopScanning()
        targetPeripheralIdentifier = nil
        inScanningMode.value = false
        resetManagerStateAfterDeactivation()

        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }
}

// MARK: - TandemPumpDelegate Conformance

@available(macOS 13.0, iOS 14.0, *) extension TandemPumpManager: TandemPumpDelegate {
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
            log.info("Creating new transport for peripheral manager")
            let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            updateTransport(transport)
        } else {
            log.info("Reusing existing transport - peripheral manager unchanged")
        }

        activePeripheralManager = peripheralManager
        pumpComm.manager = peripheralManager
        notificationRouter.start(with: peripheralManager, session: pumpComm.getSession())
    }

    public func tandemPump(
        _: TandemPump,
        didDiscoverDevice peripheral: CBPeripheral,
        advertisementData: [String: Any]?,
        rssi: NSNumber
    ) {
        log
            .info(
                "[tandemPump didDiscoverDevice] inScanningMode=\(String(describing: inScanningMode.value)) peripheral=\(String(describing: peripheral))"
            )
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
            log
                .info(
                    "[tandemPump didDiscoverDevice] expected pumpComm.pumpPeripheralUuid=\(String(describing: pumpComm.pumpPeripheralUuid))"
                )
            if peripheral.identifier.uuidString == pumpComm.pumpPeripheralUuid {
                log.info("[tandemPump didDiscoverDevice] set targetPeripheralIdentifier")
                targetPeripheralIdentifier = peripheral.identifier
            }
        }
    }

    public func tandemPump(
        _: TandemPump,
        didDisconnectWithError error: Error?
    ) {
        log.error("Pump disconnected with error: \(String(describing: error))")

        if let manager = activePeripheralManager {
            notificationRouter.stop(with: manager)
            activePeripheralManager = nil
        }

        pumpComm.manager = nil
        updateTransport(nil)

        updateStatus { status in
            status.deliveryIsUncertain = true
        }

        if isOnboarded {
            telemetryLogger.debug("Pump disconnected – restarting scan to reconnect")
            tandemPump.startScanning()
        }
    }
}

// MARK: - PumpCommDelegate Conformance

@available(macOS 13.0, iOS 14.0, *) extension TandemPumpManager: PumpCommDelegate {
    public func pumpComm(_: PumpComm, didChange pumpState: PumpState) {
        // Update the stored state when pump state changes (e.g., after pairing)
        var currentState = lockedState.value
        currentState.pumpState = pumpState
        lockedState.value = currentState
        pumpComm.syncPumpState(pumpState)
        if pumpState.valid {
            needsSessionInitialization.value = false
        }

        // Update pairing artifacts so messages will be signed with the derived secret
        updatePairingArtifacts(with: pumpState)

        notifyPumpManagerDelegateDidUpdateState()

        // The state change will be automatically persisted by Loop/Trio
        // when it calls rawState during the next cycle
    }

    public func pumpComm(
        _: PumpComm,
        didReceive message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    ) {
        notificationLogger
            .debug(
                "[notification] Received \(String(describing: type(of: message))) opCode=\(metadata?.opCode ?? type(of: message).props.opCode) characteristic=\(characteristic.prettyName) txId=\(txId)"
            )

        switch message {
        case let battery as CurrentBatteryAbstractResponse:
            handleBatteryResponse(battery, source: .notification)
        case let insulin as InsulinStatusResponse:
            handleReservoirResponse(insulin, source: .notification)
        case let basal as CurrentBasalStatusResponse:
            handleBasalResponse(basal, source: .notification)
        case let homeScreenResponse as HomeScreenMirrorResponse:
            handleHomeScreenMirrorResponse(homeScreenResponse, source: .notification)
        case let bolus as CurrentBolusStatusResponse:
            handleBolusResponse(bolus, source: .notification)
        case let timeSinceReset as TimeSinceResetResponse:
            handleTimeSinceResetResponse(timeSinceReset, source: .notification)
        case let tempRate as TempRateResponse:
            handleTempRateResponse(tempRate, source: .notification)
        case let historyStream as HistoryLogStreamResponse:
            if let session = activeHistoryFetchSession.value {
                session.handleStreamResponse(historyStream)
            } else {
                handleUnsolicitedHistoryStream(historyStream)
            }
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

        // Fetch suggested status messages for these events
        Task { @MainActor in
            let handlers = QualifyingEvent.groupSuggestedHandlers(events)
            notificationLogger.debug("[notification] Fetching \(handlers.count) status messages for qualifying events")

            for message in handlers {
                do {
                    guard let transport = pairedTransport else {
                        notificationLogger.warning("[notification] No transport available for qualifying event handler")
                        break
                    }

                    let response = try transport.sendMessage(message)
                    let metadata = MessageRegistry.metadata(for: response)

                    // Process the response through the normal notification handler
                    pumpComm(
                        pumpComm,
                        didReceive: response,
                        metadata: metadata,
                        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
                        txId: 0
                    )
                } catch {
                    notificationLogger.error("[notification] Failed to fetch handler for qualifying event: \(error)")
                }
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
}

private extension TandemPumpManager {
    func getScheduledBasalRate() -> Double {
        guard let schedule = lockedState.value.basalRateSchedule, !schedule.items.isEmpty else {
            return 0
        }

        let now = Date.now
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        return schedule.items.last(where: { $0.startTime < nowTimeInterval })?.value ?? schedule.items[0].value
    }

    func releaseBolusPermission(transport: PumpMessageTransport, bolusId: UInt32) {
        do {
            let response: BolusPermissionReleaseResponse = try pumpComm.sendMessage(
                transport: transport,
                message: BolusPermissionReleaseRequest(bolusId: bolusId),
                expecting: BolusPermissionReleaseResponse.self
            )

            if response.status != 0 {
                log.error("Failed to release bolus permission for id \(bolusId) with status \(response.status)")
            }
        } catch {
            log.error("Error releasing bolus permission for id \(bolusId): \(String(describing: error))")
        }
    }
}

private extension PumpManagerStatus.BasalDeliveryState {
    var scheduledBasalRateValue: Double? {
        switch self {
        case let .tempBasal(dose):
            if let quantity = dose.scheduledBasalRate {
                return quantity.doubleValue(for: HKUnit.internationalUnit().unitDivided(by: .hour()))
            }
            return dose.programmedUnits
        default:
            return nil
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

private extension PumpTelemetryKind {
    var logDescription: String {
        switch self {
        case .reservoir:
            return "reservoir"
        case .battery:
            return "battery"
        case .basal:
            return "basal"
        case .bolus:
            return "bolus"
        case .timeSinceReset:
            return "timeSinceReset"
        case .alerts:
            return "alerts"
        case .controlIQ:
            return "controlIQ"
        case .homeScreen:
            return "homeScreen"
        case .notifications:
            return "notifications"
        case .history:
            return "history"
        }
    }
}
