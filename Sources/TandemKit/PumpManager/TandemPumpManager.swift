import CoreBluetooth
import Dispatch
import Foundation
#if canImport(HealthKit)
    import HealthKit
#endif
#if canImport(os)
    import os.log
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

// Simple delegate wrapper
// private class WeakSynchronizedDelegate<T> {
//    private weak var _value: AnyObject?
//    var _queue = DispatchQueue.main
//
//    var value: T? {
//        get {
//            _queue.sync { _value as? T }
//        }
//        set {
//            _queue.sync { _value = newValue as AnyObject? }
//        }
//    }
//
//    var queue: DispatchQueue {
//        get { _queue }
//        set { _queue = newValue }
//    }
// }

// Simple Locked wrapper
private class Locked<Value> {
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
    let dose: DoseEntry
}

private struct ActiveTempBasal {
    let dose: DoseEntry
    let scheduledRate: Double
}

@available(macOS 13.0, iOS 14.0, *)
public class TandemPumpManager: PumpManager, Pluggable {
    public static var pluginIdentifier: String = "TandemPumpManager"

    public var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    public static let onboardingMaximumBasalScheduleEntryCount: Int = 24
    public static let onboardingSupportedBasalRates: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0, 1.5, 2.0]
    public static let onboardingSupportedBolusVolumes: [Double] = [0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 3.0, 5.0]
    public static let onboardingSupportedMaximumBolusVolumes: [Double] = onboardingSupportedBolusVolumes

    public typealias RawStateValue = [String: Any]

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    public let tandemPump: TandemPump
    private let log = OSLog(category: "TandemPumpManager")
    private let telemetryScheduler = PumpTelemetryScheduler(label: "com.jwoglom.TandemKit.telemetry")
    private let telemetryLogger = PumpLogger(label: "TandemKit.TandemPumpManager.Telemetry")
    private let notificationRouter = PumpNotificationRouter()
    private let notificationLogger = PumpLogger(label: "TandemKit.TandemPumpManager.Notifications")

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
    private let lastScheduledBasalRate = Locked<Double?>(nil)
    private let lockedBatteryChargeRemaining: Locked<Double?>
    private let lockedReservoirValue: Locked<ReservoirValue?>
    private let lockedCurrentBasalRate = Locked<Double?>(nil)
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
        lockedCurrentBasalRate.value = nil
        lastScheduledBasalRate.value = nil
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

        tandemPump.state = nil
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
            log.info("updateTransport: setting transport instance=%{public}@", String(describing: instanceId))
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
            telemetryScheduler.triggerAll()
            return
        }

        if sessionBootstrapInProgress.value {
            telemetryLogger.debug("Session bootstrap already in progress; skipping duplicate trigger")
            return
        }

        sessionBootstrapInProgress.value = true

        sessionInitializationQueue.async { [weak self] in
            guard let self = self else { return }
            self.telemetryLogger.debug("Running authenticated session bootstrap to refresh timeSinceReset")

            do {
                let response: TimeSinceResetResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: TimeSinceResetRequest(),
                    expecting: TimeSinceResetResponse.self
                )

                self.handleTimeSinceResetResponse(response, source: .telemetry)
                self.needsSessionInitialization.value = false
                self.sessionBootstrapRetryAttempt.value = 0
                self.telemetryLogger.debug("Session bootstrap complete – triggering telemetry refresh")
                self.telemetryScheduler.triggerAll()
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

    private func logger(for source: ResponseSource) -> PumpLogger {
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
        lockedStatus = Locked(Self.makeStatus(from: state))
        lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        lockedReservoirValue = Locked(state.lastReservoirReading)
        tandemPump = TandemPump(state.pumpState)
        needsSessionInitialization.value = state.pumpState?.valid == true

        tandemPump.delegate = self
        pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        tandemPump.configureDeliveryActions(enabled: state.insulinDeliveryActionsEnabled)
        tandemPump.configureConnectionSharing(enabled: state.connectionSharingEnabled)
        setupTelemetry()
    }

    public required init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else {
            return nil
        }

        lockedState = Locked(state)
        lockedStatus = Locked(Self.makeStatus(from: state))
        lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        lockedReservoirValue = Locked(state.lastReservoirReading)
        tandemPump = TandemPump(state.pumpState)
        needsSessionInitialization.value = state.pumpState?.valid == true

        tandemPump.delegate = self
        pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        tandemPump.configureDeliveryActions(enabled: state.insulinDeliveryActionsEnabled)
        tandemPump.configureConnectionSharing(enabled: state.connectionSharingEnabled)
        setupTelemetry()

        print("Initialized TandemPumpManager: state=\(state)")

        if state.pumpState?.valid == true {
            // start connection
            tandemPump.startScanning()
        }
    }

    deinit {
        telemetryScheduler.cancelAll()
    }

    public var rawState: RawStateValue {
        lockedState.value.rawValue
    }

    public var debugDescription: String {
        "TandemPumpManager(state: \(lockedState.value))"
    }

    // TODO(jwoglom): replace with connectedAndPaired?
    public var isOnboarded: Bool {
        lockedState.value.pumpState != nil
    }

    public var connectedAndPaired: Bool {
        guard let _ = transportLock.value else {
            return false
        }
        guard pumpComm.isDevicePaired else {
            return false
        }
        if lockedState.value.pumpState == nil {
            return false
        }

        return true
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

    // MARK: - Pump Capabilities

    public var supportedBasalRates: [Double] {
        // Tandem t:slim X2 supports 0.001 to 35.0 U/hr in 0.001 U increments
        stride(from: 0.001, through: 35.0, by: 0.001).map { $0 }
    }

    public var supportedBolusVolumes: [Double] {
        // Tandem t:slim X2 supports 0.01 to 25.0 U in 0.01 U increments
        stride(from: 0.01, through: 25.0, by: 0.01).map { $0 }
    }

    public var supportedMaximumBolusVolumes: [Double] {
        supportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        24 // One entry per hour
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        30 * 60 // 30 minutes in seconds
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        false // Tandem pumps do not explicitly record basal profile start events
    }

    public var pumpReservoirCapacity: Double {
        300.0 // t:slim X2 reservoir capacity in units
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

    private func setupTelemetry() {
        guard !telemetryConfigured else { return }
        telemetryConfigured = true

        telemetryScheduler.schedule(kind: .basal, interval: 5 * 60) { [weak self] in
            self?.fetchBasalStatus()
        }

        telemetryScheduler.schedule(kind: .reservoir, interval: 5 * 60) { [weak self] in
            self?.fetchReservoirStatus()
        }

        telemetryScheduler.schedule(kind: .battery, interval: 30 * 60) { [weak self] in
            self?.fetchBatteryStatus()
        }

        telemetryScheduler.schedule(kind: .bolus, interval: 60) { [weak self] in
            self?.fetchBolusStatus()
        }

        // NOTE: TimeSinceResetRequest causes timeouts and disconnections on some pumps
        // Disabled for now - will use default value of 0
        // telemetryScheduler.schedule(kind: .timeSinceReset, interval: 5 * 60) { [weak self] in
        //     self?.fetchTimeSinceReset()
        // }
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
        let units = Double(response.currentInsulinAmount) / 1000.0
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
        lockedCurrentBasalRate.value = rateUnitsPerHour
        let timestamp = Date()

        logger(for: source).debug("[\(source.label)] Basal updated: \(String(format: "%.3f", rateUnitsPerHour)) U/hr")

        let newBasalState: PumpManagerStatus.BasalDeliveryState
        if rateUnitsPerHour <= 0 {
            newBasalState = .suspended(timestamp)
        } else {
            newBasalState = .active(timestamp)
        }

        updateStatus { status in
            status.basalDeliveryState = newBasalState
        }

        var managerState = lockedState.value
        managerState.basalDeliveryState = newBasalState
        managerState.lastBasalStatusDate = timestamp
        lockedState.value = managerState

        notifyDelegateStateUpdated()
    }

    private func handleBolusResponse(_ response: CurrentBolusStatusResponse, source: ResponseSource) {
        logger(for: source)
            .debug("[\(source.label)] Bolus status response received statusId=\(response.statusId) bolusId=\(response.bolusId)")

        guard response.isValid else {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            notifyDelegateStateUpdated()
            return
        }

        let requestedUnits = Double(response.requestedVolume) / 1000.0
        let bolusDate = response.timestampDate
        let dose = DoseEntry(
            type: .bolus,
            startDate: bolusDate,
            endDate: bolusDate,
            value: requestedUnits,
            unit: .units,
            deliveredUnits: nil,
            description: "Bolus \(response.bolusId)",
            syncIdentifier: "bolus-\(response.bolusId)",
            scheduledBasalRate: nil,
            insulinType: nil,
            automatic: nil,
            manuallyEntered: false,
            isMutable: true,
            wasProgrammedByPumpUI: false
        )

        let newBolusState: PumpManagerStatus.BolusState
        if let status = response.status {
            switch status {
            case .alreadyDeliveredOrInvalid:
                newBolusState = .noBolus
            case .delivering,
                 .requesting:
                newBolusState = .inProgress(dose)
            }
        } else {
            newBolusState = .noBolus
        }

        updateStatus { status in
            status.bolusState = newBolusState
        }

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
            needsSessionInitialization.value = false

            // Update the PumpStateSupplier with the new value
            updatePairingArtifacts(with: pumpState)

            notifyDelegateStateUpdated()
        }
    }

    private func makeBatteryRequest() -> Message {
        let apiVersion = PumpStateSupplier.currentPumpApiVersion() ?? KnownApiVersion.apiV2_1.value
        return CurrentBatteryRequestBuilder.create(apiVersion: apiVersion)
    }

    private func fetchBatteryStatus() {
        guard let transport = pairedTransport else {
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
        guard let transport = pairedTransport else {
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
        guard let transport = pairedTransport else {
            return
        }

        do {
            telemetryLogger.debug("Requesting message fetchBasalStatus")
            let response = try pumpComm.sendMessage(
                transport: transport,
                message: CurrentBasalStatusRequest(),
                expecting: CurrentBasalStatusResponse.self
            )

            handleBasalResponse(response, source: .telemetry)
        } catch {
            telemetryLogger.error("Basal telemetry request failed: \(error)")
        }
    }

    private func fetchBolusStatus() {
        guard let transport = pairedTransport else {
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
        guard let transport = pairedTransport else {
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

    private func notifyDelegateStateUpdated() {
        guard let delegate = pumpManagerDelegate else { return }
        pumpDelegate.queue.async { [weak self] in
            guard let self = self else { return }
            delegate.pumpManagerDidUpdateState(self)
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

    internal func notifyScanDeviceDidChange(_ device: TandemPumpScan) {
        DispatchQueue.main.async {
            self.scanDeviceObservers.forEach { observer in
                observer.deviceScanDidUpdate(device)
            }
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

    private func notifyPumpManagerDelegateDidUpdateState() {
        guard let delegate = pumpManagerDelegate, let queue = delegateQueue else { return }
        queue.async {
            delegate.pumpManagerDidUpdateState(self)
        }
    }

    private func completeBolus(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerError?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            switch result {
            case .success:
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
            completion(result)
        }
    }

    private func completeTempBasal(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerError?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            switch result {
            case .success:
                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    private func completeSuspend(_ error: Error?, completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            completion(error)
        }
    }

    private func completeResume(_ error: Error?, completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            completion(error)
        }
    }

    private func scheduledBasalRateForTempBasal(requestedRate: Double) -> Double {
        if let override = lastScheduledBasalRate.value, override > 0 {
            return override
        }

        if let statusRate = lockedStatus.value.basalDeliveryState?.scheduledBasalRateValue, statusRate > 0 {
            return statusRate
        }

        return max(requestedRate, 0.05)
    }

    private func percentForTempBasal(requestedRate: Double, baseline: Double) -> Int {
        guard baseline > 0 else { return 0 }
        let percent = Int((requestedRate / baseline * 100.0).rounded())
        return max(0, min(percent, 500))
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
            telemetryScheduler.triggerAll()
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

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        completion?(lockedState.value.lastReconciliation)
    }

    public func setMustProvideBLEHeartbeat(_: Bool) {
        // Store this setting to control heartbeat behavior
        // The actual heartbeat logic will be implemented in future pump communication
    }

    public func createBolusProgressReporter(reportingOn _: DispatchQueue) -> DoseProgressReporter? {
        // This will be implemented when we support bolus delivery
        // For now, return nil to indicate no active bolus
        nil
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
                    print("Waiting for peripheral to be in connected state, in \(peripheral.state): \(peripheral)")
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
                    print("Waiting for transport to be initialized...")
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
                    DispatchQueue.global(qos: .userInitiated).async { [pumpComm, weak self, telemetryScheduler] in
                        do {
                            // pair() now handles: JPAKE + 250ms wait + TimeSinceResetRequest
                            try pumpComm.pair(transport: transport, peripheralUuid: peripheralUuid, pairingCode: sanitizedCode)

                            // After successful pairing and session initialization, trigger initial telemetry refresh
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                self.telemetryLogger.debug("Pairing complete – triggering initial telemetry refresh")
                                telemetryScheduler.triggerAll()
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

        let startDate = Date()
        let syncIdentifier = UUID().uuidString
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: nil,
            value: units,
            unit: .units,
            deliveredUnits: nil,
            description: nil,
            syncIdentifier: syncIdentifier,
            scheduledBasalRate: nil,
            insulinType: nil,
            automatic: activationType.isAutomatic,
            manuallyEntered: !activationType.isAutomatic,
            isMutable: true,
            wasProgrammedByPumpUI: false
        )

        updateStatus { status in
            status.bolusState = .initiating
        }

        guard let transport = pairedTransport else {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeBolus(.failure(.communication(error)), completion: completion)
            return
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

                shouldReleasePermissionOnFailure = false

                self.activeBolus.value = ActiveBolus(
                    id: initiateResponse.bolusId,
                    dose: dose
                )

                self.updateStatus { status in
                    status.bolusState = .inProgress(dose)
                }

                self.recordReconciliation(at: Date())
                self.completeBolus(.success(dose), completion: completion)
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

                self.activeBolus.value = nil
                let endDate = Date()
                let canceledDose = DoseEntry(
                    type: .bolus,
                    startDate: active.dose.startDate,
                    endDate: endDate,
                    value: active.dose.programmedUnits,
                    unit: active.dose.unit,
                    deliveredUnits: active.dose.deliveredUnits,
                    syncIdentifier: active.dose.syncIdentifier,
                    scheduledBasalRate: active.dose.scheduledBasalRate
                )

                self.updateStatus { status in
                    status.bolusState = .noBolus
                }

                self.recordReconciliation(at: endDate)
                self.completeCancelBolus(.success(canceledDose), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.bolusState = .inProgress(active.dose)
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
        if let error = validateTempBasalRequest(unitsPerHour: unitsPerHour, duration: duration) {
            completeTempBasal(.failure(error), completion: completion)
            return
        }

        let startDate = Date()
        let previousStatus = lockedStatus.value
        if duration <= 0 {
            updateStatus { status in
                status.basalDeliveryState = .cancelingTempBasal
            }
        } else {
            updateStatus { status in
                status.basalDeliveryState = .initiatingTempBasal
            }
        }

        guard let transport = pairedTransport else {
            updateStatus { status in
                status.basalDeliveryState = previousStatus.basalDeliveryState
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeTempBasal(.failure(.communication(error)), completion: completion)
            return
        }

        let baselineRate = scheduledBasalRateForTempBasal(requestedRate: unitsPerHour)
        let scheduledQuantity = HKQuantity(unit: HKUnit.internationalUnit().unitDivided(by: .hour()), doubleValue: baselineRate)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                if duration <= 0 {
                    let response: StopTempRateResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: StopTempRateRequest(),
                        expecting: StopTempRateResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    let endDate = Date()
                    let cancellationDose: DoseEntry
                    if let active = self.activeTempBasal.value {
                        cancellationDose = DoseEntry(
                            type: .tempBasal,
                            startDate: active.dose.startDate,
                            endDate: endDate,
                            value: active.dose.programmedUnits,
                            unit: active.dose.unit,
                            deliveredUnits: active.dose.deliveredUnits,
                            syncIdentifier: active.dose.syncIdentifier,
                            scheduledBasalRate: active.dose.scheduledBasalRate
                        )
                    } else {
                        cancellationDose = DoseEntry(
                            type: .tempBasal,
                            startDate: endDate,
                            endDate: endDate,
                            value: 0,
                            unit: .unitsPerHour,
                            deliveredUnits: nil,
                            syncIdentifier: UUID().uuidString,
                            scheduledBasalRate: scheduledQuantity
                        )
                    }

                    self.activeTempBasal.value = nil
                    self.lastScheduledBasalRate.value = nil

                    self.updateStatus { status in
                        status.basalDeliveryState = .active(Date())
                    }

                    self.recordReconciliation(at: endDate)
                    self.completeTempBasal(.success(cancellationDose), completion: completion)
                } else {
                    let minutes = max(1, Int((duration / 60.0).rounded()))
                    let percent = self.percentForTempBasal(requestedRate: unitsPerHour, baseline: baselineRate)

                    let request = SetTempRateRequest(minutes: minutes, percent: percent)
                    let response: SetTempRateResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: request,
                        expecting: SetTempRateResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    let endDate = startDate.addingTimeInterval(duration)
                    let dose = DoseEntry(
                        type: .tempBasal,
                        startDate: startDate,
                        endDate: endDate,
                        value: unitsPerHour,
                        unit: .unitsPerHour,
                        deliveredUnits: nil,
                        syncIdentifier: UUID().uuidString,
                        scheduledBasalRate: scheduledQuantity
                    )

                    self.activeTempBasal.value = ActiveTempBasal(dose: dose, scheduledRate: baselineRate)
                    self.lastScheduledBasalRate.value = baselineRate

                    self.updateStatus { status in
                        status.basalDeliveryState = .tempBasal(dose)
                    }

                    self.recordReconciliation(at: startDate)
                    self.completeTempBasal(.success(dose), completion: completion)
                }
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
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

    private func validateTempBasalRequest(unitsPerHour: Double, duration: TimeInterval) -> PumpManagerError? {
        guard unitsPerHour >= 0 else {
            return .deviceState(TandemPumpManagerValidationError.invalidTempBasalRate(requested: unitsPerHour))
        }

        if let maxRate = currentSettings.maxTempBasalRate, unitsPerHour > maxRate {
            return .deviceState(
                TandemPumpManagerValidationError.maximumTempBasalRateExceeded(
                    requested: unitsPerHour,
                    maximum: maxRate
                )
            )
        }

        if duration <= 0 {
            return .deviceState(TandemPumpManagerValidationError.invalidTempBasalDuration(requested: duration))
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
            completeSuspend(error, completion: completion)
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

                let suspendDate = Date()
                self.activeTempBasal.value = nil
                self.lastScheduledBasalRate.value = nil

                self.updateStatus { status in
                    status.basalDeliveryState = .suspended(suspendDate)
                    status.bolusState = .noBolus
                }

                self.recordReconciliation(at: suspendDate)
                self.completeSuspend(nil, completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeSuspend(pumpError, completion: completion)
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
            completeResume(error, completion: completion)
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

                let resumeDate = Date()
                self.activeTempBasal.value = nil
                self.lastScheduledBasalRate.value = nil
                self.updateStatus { status in
                    status.basalDeliveryState = .active(resumeDate)
                }

                self.recordReconciliation(at: resumeDate)
                self.completeResume(nil, completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.transportError(underlying: error)
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeResume(pumpError, completion: completion)
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
        let requests = makeBasalSegmentRequests(from: sortedItems)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                for request in requests {
                    let response: SetIDPSegmentResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: request,
                        expecting: SetIDPSegmentResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }
                }

                let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: self.lockedStatus.value.timeZone)

                var managerState = self.lockedState.value
                managerState.basalRateSchedule = schedule
                managerState.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
                self.lockedState.value = managerState

                if let firstRate = sortedItems.first?.value {
                    self.lastScheduledBasalRate.value = firstRate
                }

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

@available(macOS 13.0, iOS 14.0, *)
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
        log.info(
            "[tandemPump didDiscoverDevice] inScanningMode=%{public}@ peripheral=%{public}@",
            String(describing: inScanningMode.value),
            String(describing: peripheral)
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
            log.info(
                "[tandemPump didDiscoverDevice] expected pumpComm.pumpPeripheralUuid=%s",
                String(describing: pumpComm.pumpPeripheralUuid)
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
        log.error("Pump disconnected with error: %{public}@", String(describing: error))

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

@available(macOS 13.0, iOS 14.0, *)
extension TandemPumpManager: PumpCommDelegate {
    public func pumpComm(_: PumpComm, didChange pumpState: PumpState) {
        // Update the stored state when pump state changes (e.g., after pairing)
        var currentState = lockedState.value
        currentState.pumpState = pumpState
        lockedState.value = currentState
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
        case let bolus as CurrentBolusStatusResponse:
            handleBolusResponse(bolus, source: .notification)
        case let timeSinceReset as TimeSinceResetResponse:
            handleTimeSinceResetResponse(timeSinceReset, source: .notification)
        default:
            if let meta = metadata {
                notificationLogger.debug("[notification] Ignoring \(meta.name) on \(characteristic.prettyName)")
            } else {
                notificationLogger.debug("[notification] Ignoring message type=\(String(describing: type(of: message)))")
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
    func makeBasalSegmentRequests(from items: [RepeatingScheduleValue<Double>]) -> [SetIDPSegmentRequest] {
        let idpId = 0
        let unknownId = 1
        let mask = idpStatusMask([.BASAL_RATE, .START_TIME])

        return items.enumerated().map { index, entry in
            let startMinutes = Int((entry.startTime / 60.0).rounded())
            let basalMilliunits = Int((entry.value * 1000.0).rounded())

            return SetIDPSegmentRequest(
                idpId: idpId,
                unknownId: unknownId,
                segmentIndex: index,
                operation: .modifySegmentId,
                profileStartTime: startMinutes,
                profileBasalRate: basalMilliunits,
                profileCarbRatio: 0,
                profileTargetBG: 0,
                profileISF: 0,
                idpStatusId: mask
            )
        }
    }

    func idpStatusMask(_ statuses: Set<IDPSegmentResponse.IDPSegmentStatus>) -> Int {
        statuses.reduce(0) { $0 | $1.rawValue }
    }

    func releaseBolusPermission(transport: PumpMessageTransport, bolusId: UInt32) {
        do {
            let response: BolusPermissionReleaseResponse = try pumpComm.sendMessage(
                transport: transport,
                message: BolusPermissionReleaseRequest(bolusId: bolusId),
                expecting: BolusPermissionReleaseResponse.self
            )

            if response.status != 0 {
                log.error("Failed to release bolus permission for id %{public}u with status %{public}d", bolusId, response.status)
            }
        } catch {
            log.error("Error releasing bolus permission for id %{public}u: %{public}@", bolusId, String(describing: error))
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
