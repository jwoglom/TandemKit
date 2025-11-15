//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import Dispatch
import CoreBluetooth
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(os)
import os.log
#endif
import LoopKit
import TandemCore
import TandemBLE
#if canImport(UIKit)
import UIKit
#endif

// Simple delegate wrapper
private class WeakSynchronizedDelegate<T> {
    private weak var _value: AnyObject?
    var _queue: DispatchQueue = DispatchQueue.main

    var value: T? {
        get {
            return _queue.sync { _value as? T }
        }
        set {
            _queue.sync { _value = newValue as AnyObject? }
        }
    }

    var queue: DispatchQueue {
        get { _queue }
        set { _queue = newValue }
    }
}

// Simple Locked wrapper
private class Locked<Value> {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
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
public class TandemPumpManager: PumpManager {
    public static var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    public static let onboardingMaximumBasalScheduleEntryCount: Int = 24
    public static let onboardingSupportedBasalRates: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0, 1.5, 2.0]
    public static let onboardingSupportedBolusVolumes: [Double] = [0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 3.0, 5.0]
    public static let onboardingSupportedMaximumBolusVolumes: [Double] = onboardingSupportedBolusVolumes

    public typealias RawStateValue = [String: Any]

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let dosingDelegate = WeakSynchronizedDelegate<PumpManagerDosingDecisionDelegate>()
    private let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    private let tandemPump: TandemPump
    private let log = OSLog(category: "TandemPumpManager")
    private let telemetryScheduler = PumpTelemetryScheduler(label: "com.jwoglom.TandemKit.telemetry")
    private let telemetryLogger = PumpLogger(label: "TandemKit.TandemPumpManager.Telemetry")
    private let notificationRouter = PumpNotificationRouter()
    private let notificationLogger = PumpLogger(label: "TandemKit.TandemPumpManager.Notifications")

    // Status tracking
    private let statusObservers = Locked<[UUID: (observer: PumpManagerStatusObserver, queue: DispatchQueue)]>([:])
    private let lockedStatus: Locked<PumpManagerStatus>
    private let activeBolus = Locked<ActiveBolus?>(nil)
    private let activeTempBasal = Locked<ActiveTempBasal?>(nil)
    private let lastScheduledBasalRate = Locked<Double?>(nil)
    private let lockedBatteryChargeRemaining: Locked<Double?>
    private let lockedReservoirValue: Locked<ReservoirValue?>
    private let lockedCurrentBasalRate = Locked<Double?>(nil)
    private var telemetryConfigured = false
    private weak var activePeripheralManager: PeripheralManager?

    private func updatePairingArtifacts(with pumpState: PumpState?) {
#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
        let derivedSecret = pumpState?.derivedSecret
        let serverNonce = pumpState?.serverNonce
        PumpStateSupplier.storePairingArtifacts(derivedSecret: derivedSecret, serverNonce: serverNonce)
#endif
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    private var pumpComm: PumpComm {
        get {
            return tandemPump.pumpComm
        }
        set {
            tandemPump.pumpComm = newValue
        }
    }

    public func updateTransport(_ transport: PumpMessageTransport?) {
        transportLock.value = transport

        if let peripheralManager = activePeripheralManager, transport != nil {
            pumpComm.manager = peripheralManager
        } else if transport == nil {
            pumpComm.manager = nil
        }

        if transport != nil {
            telemetryLogger.debug("Transport available – triggering telemetry refresh")
            updateStatus { status in
                status.deliveryIsUncertain = false
            }
            telemetryScheduler.triggerAll()
        } else {
            telemetryLogger.debug("Transport cleared – telemetry will pause until reconnect")
            updateStatus { status in
                status.deliveryIsUncertain = true
            }
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
        return PumpManagerStatus(
            timeZone: TimeZone.current,
            device: HKDevice(
                name: "TandemPump",
                manufacturer: "Tandem",
                model: "t:slim X2",
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
        status.basalDeliveryState = state.basalDeliveryState ?? status.basalDeliveryState
        status.bolusState = state.bolusState
        status.deliveryIsUncertain = state.deliveryIsUncertain
        status.pumpBatteryChargeRemaining = state.lastBatteryReading?.chargeRemaining
        return status
    }

    public init(state: TandemPumpManagerState) {
        self.lockedState = Locked(state)
        self.lockedStatus = Locked(Self.makeStatus(from: state))
        self.lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        self.lockedReservoirValue = Locked(state.lastReservoirReading)
        self.tandemPump = TandemPump(state.pumpState)

        self.tandemPump.delegate = self
        self.pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        setupTelemetry()
    }

    public required init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else {
            return nil
        }

        self.lockedState = Locked(state)
        self.lockedStatus = Locked(Self.makeStatus(from: state))
        self.lockedBatteryChargeRemaining = Locked(state.lastBatteryReading?.chargeRemaining)
        self.lockedReservoirValue = Locked(state.lastReservoirReading)
        self.tandemPump = TandemPump(state.pumpState)

        self.tandemPump.delegate = self
        self.pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
        setupTelemetry()
    }

    deinit {
        telemetryScheduler.cancelAll()
    }

    public var rawState: RawStateValue {
        return lockedState.value.rawValue
    }

    public var debugDescription: String {
        return "TandemPumpManager(state: \(lockedState.value))"
    }

    public var isOnboarded: Bool {
        return lockedState.value.pumpState != nil
    }

    // MARK: - Pump Capabilities

    public var supportedBasalRates: [Double] {
        // Tandem t:slim X2 supports 0.001 to 35.0 U/hr in 0.001 U increments
        return stride(from: 0.001, through: 35.0, by: 0.001).map { $0 }
    }

    public var supportedBolusVolumes: [Double] {
        // Tandem t:slim X2 supports 0.01 to 25.0 U in 0.01 U increments
        return stride(from: 0.01, through: 25.0, by: 0.01).map { $0 }
    }

    public var supportedMaximumBolusVolumes: [Double] {
        return supportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        return 24 // One entry per hour
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        return 30 * 60 // 30 minutes in seconds
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        return false // Tandem pumps do not explicitly record basal profile start events
    }

    public var pumpReservoirCapacity: Double {
        return 300.0 // t:slim X2 reservoir capacity in units
    }

    public var lastSync: Date? {
        return lockedState.value.lastReconciliation
    }

    public var status: PumpManagerStatus {
        return lockedStatus.value
    }

    public var pumpStatus: PumpManagerStatus {
        return lockedStatus.value
    }

    public var pumpBatteryChargeRemaining: Double? {
        return lockedBatteryChargeRemaining.value
    }

    public var reservoirLevel: ReservoirValue? {
        return lockedReservoirValue.value
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
        logger(for: source).debug("[\(source.label)] Bolus status response received statusId=\(response.statusId) bolusId=\(response.bolusId)")

        guard response.isValid else {
            updateStatus { status in
                status.bolusState = .noBolus
            }
            notifyDelegateStateUpdated()
            return
        }

        let requestedUnits = Double(response.requestedVolume) / 1000.0
        let bolusDate = response.timestampDate
        let dose = DoseEntry(type: .bolus,
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
                             wasProgrammedByPumpUI: false)

        let newBolusState: PumpManagerStatus.BolusState
        if let status = response.status {
            switch status {
            case .alreadyDeliveredOrInvalid:
                newBolusState = .noBolus
            case .delivering, .requesting:
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

    private func makeBatteryRequest() -> Message {
        let apiVersion = PumpStateSupplier.currentPumpApiVersion() ?? KnownApiVersion.apiV2_1.value
        return CurrentBatteryRequestBuilder.create(apiVersion: apiVersion)
    }

    private func fetchBatteryStatus() {
        guard let transport = transportLock.value else {
            telemetryLogger.debug("Skipping battery telemetry – no transport")
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
                telemetryLogger.error("Battery telemetry request builder returned unsupported type: \(String(describing: type(of: request)))")
            }
        } catch {
            telemetryLogger.error("Battery telemetry request failed: \(error)")
        }
    }

    private func fetchReservoirStatus() {
        guard let transport = transportLock.value else {
            telemetryLogger.debug("Skipping reservoir telemetry – no transport")
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
        guard let transport = transportLock.value else {
            telemetryLogger.debug("Skipping basal telemetry – no transport")
            return
        }

        do {
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
        guard let transport = transportLock.value else {
            telemetryLogger.debug("Skipping bolus telemetry – no transport")
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
                case .failure(let error):
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
            return value.observer !== observer
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

    private func currentTransport() -> PumpMessageTransport? {
        return transportLock.value
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
            case .failure(let error):
                completion(error)
            }

            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didEnactBolus: result)
            }
        }
    }

    private func completeCancelBolus(_ result: PumpManagerResult<DoseEntry?>, completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            completion(result)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didCancelBolus: result)
            }
        }
    }

    private func completeTempBasal(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerError?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            switch result {
            case .success:
                completion(nil)
            case .failure(let error):
                completion(error)
            }

            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didEnactTempBasal: result)
            }
        }
    }

    private func completeSuspend(_ error: Error?, completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            completion(error)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didSuspendDeliveryWithError: error)
            }
        }
    }

    private func completeResume(_ error: Error?, completion: @escaping (Error?) -> Void) {
        guard let queue = delegateQueue else { return }
        queue.async {
            completion(error)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didResumeDeliveryWithError: error)
            }
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
            return pumpDelegate.value
        }
        set {
            pumpDelegate.value = newValue
        }
    }

    public var dosingDecisionDelegate: PumpManagerDosingDecisionDelegate? {
        get {
            return dosingDelegate.value
        }
        set {
            dosingDelegate.value = newValue
        }
    }

    public func connect() {
        tandemPump.delegate = self
        pumpComm.delegate = self

        if currentTransport() != nil {
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

    // MARK: - PumpManager Additional Methods

    public func ensureCurrentPumpData(completion: ((_ lastSync: Date?) -> Void)?) {
        completion?(lockedState.value.lastReconciliation)
    }

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        // Store this setting to control heartbeat behavior
        // The actual heartbeat logic will be implemented in future pump communication
    }

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        // This will be implemented when we support bolus delivery
        // For now, return nil to indicate no active bolus
        return nil
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        // Tandem pumps typically deliver at up to 1 unit every 5 seconds.
        // Use a conservative estimate of 30 seconds per unit for now.
        return max(units, 0) * 30.0
    }

#if canImport(UIKit)
    public func pairPump(with pairingCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let sanitizedCode = try PumpStateSupplier.sanitizeAndStorePairingCode(pairingCode)
            tandemPump.startScanning()

            guard let transport = transportLock.value else {
                completion(.failure(PumpCommError.pumpNotConnected))
                return
            }

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            DispatchQueue.global(qos: .userInitiated).async { [pumpComm] in
                do {
                    try pumpComm.pair(transport: transport, pairingCode: sanitizedCode)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
#else
            completion(.failure(PumpCommError.other))
#endif
        } catch {
            completion(.failure(error))
        }
    }
#endif

    // MARK: - Dose Delivery Methods

    public func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (_ error: PumpManagerError?) -> Void) {
        if let error = validateBolusRequest(units: units, activationType) {
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

        guard let transport = currentTransport() else {
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

                let initiateResponse: InitiateBolusResponse = try self.pumpComm.sendMessage(
                    transport: transport,
                    message: bolusRequest,
                    expecting: InitiateBolusResponse.self
                )

                guard initiateResponse.wasBolusInitiated else {
                    throw PumpCommError.errorResponse(response: initiateResponse)
                }

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
                let pumpError = error as? PumpCommError ?? PumpCommError.other
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

        guard let transport = currentTransport() else {
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
            let error = PumpCommError.other
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
                    value: active.dose.value,
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
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.updateStatus { status in
                    status.bolusState = .inProgress(active.dose)
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeCancelBolus(.failure(.communication(pumpError)), completion: completion)
            }
        }
    }

    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (_ error: PumpManagerError?) -> Void) {
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

        guard let transport = currentTransport() else {
            updateStatus { status in
                status.basalDeliveryState = previousStatus.basalDeliveryState
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeTempBasal(.failure(.communication(error)), completion: completion)
            return
        }

        let baselineRate = scheduledBasalRateForTempBasal(requestedRate: unitsPerHour)
        let scheduledQuantity = HKQuantity(unit: HKUnit.internationalUnitPerHour(), doubleValue: baselineRate)

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
                            value: active.dose.value,
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
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeTempBasal(.failure(.communication(pumpError)), completion: completion)
            }
        }
    }

    private var currentSettings: TandemPumpManagerSettings {
        return lockedState.value.settings
    }

    private var latestInsulinOnBoard: Double? {
        return lockedState.value.latestInsulinOnBoard
    }

    private func validateBolusRequest(units: Double, _ activationType: BolusActivationType) -> PumpManagerError? {
        guard units > 0 else {
            return .deviceState(TandemPumpManagerValidationError.invalidBolusAmount(requested: units))
        }

        if let maxBolus = currentSettings.maxBolus, units > maxBolus {
            return .deviceState(TandemPumpManagerValidationError.maximumBolusExceeded(requested: units, maximum: maxBolus))
        }

        if let maxIOB = currentSettings.maxInsulinOnBoard,
           let currentIOB = latestInsulinOnBoard,
           currentIOB + units > maxIOB {
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

        guard let transport = currentTransport() else {
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
                let pumpError = error as? PumpCommError ?? PumpCommError.other
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

        guard let transport = currentTransport() else {
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
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.updateStatus { status in
                    status.basalDeliveryState = previousStatus.basalDeliveryState
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeResume(pumpError, completion: completion)
            }
        }
    }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void) {
        guard !scheduleItems.isEmpty else {
            delegateQueue.async {
                completion(.failure(PumpManagerError.configuration(nil)))
            }
            return
        }

        guard let transport = currentTransport() else {
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

                let schedule = BasalRateSchedule(items: sortedItems, timeZone: self.lockedStatus.value.timeZone)

                var managerState = self.lockedState.value
                managerState.basalRateSchedule = schedule
                managerState.settings.maxBasalScheduleEntry = sortedItems.map { $0.value }.max()
                self.lockedState.value = managerState

                if let firstRate = sortedItems.first?.value {
                    self.lastScheduledBasalRate.value = firstRate
                }

                self.notifyDelegateStateUpdated()

                self.delegateQueue.async {
                    completion(.success(schedule))
                }
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.delegateQueue.async {
                    completion(.failure(PumpManagerError.communication(pumpError)))
                }
            }
        }
    }

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void) {
        guard let transport = currentTransport() else {
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
                var appliedLimits = DeliveryLimits(maximumBasalRatePerHour: nil, maximumBolus: nil)

                if let maxBasal = deliveryLimits.maximumBasalRatePerHour {
                    let milliunits = Int((maxBasal * 1000.0).rounded())
                    let response: SetMaxBasalLimitResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: milliunits),
                        expecting: SetMaxBasalLimitResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    appliedLimits.maximumBasalRatePerHour = maxBasal
                }

                if let maxBolus = deliveryLimits.maximumBolus {
                    let milliunits = Int((maxBolus * 1000.0).rounded())
                    let response: SetMaxBolusLimitResponse = try self.pumpComm.sendMessage(
                        transport: transport,
                        message: SetMaxBolusLimitRequest(maxBolusMilliunits: milliunits),
                        expecting: SetMaxBolusLimitResponse.self
                    )

                    guard response.status == 0 else {
                        throw PumpCommError.errorResponse(response: response)
                    }

                    appliedLimits.maximumBolus = maxBolus
                }

                var managerState = self.lockedState.value
                managerState.settings.maxTempBasalRate = appliedLimits.maximumBasalRatePerHour
                managerState.settings.maxBolus = appliedLimits.maximumBolus
                self.lockedState.value = managerState

                self.notifyDelegateStateUpdated()

                self.delegateQueue.async {
                    completion(.success(appliedLimits))
                }
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.delegateQueue.async {
                    completion(.failure(PumpManagerError.communication(pumpError)))
                }
            }
        }
    }

    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        notifyDelegateOfDeactivation {
            completion(nil)
        }
    }
}

@available(macOS 13.0, iOS 14.0, *)
extension TandemPumpManager: PumpManagerUI {
#if canImport(UIKit)
    public func pairingViewController(onFinished: @escaping (Result<Void, Error>) -> Void) -> UIViewController {
        return TandemPumpPairingViewController(pumpManager: self, completion: onFinished)
    }
#endif
}

// MARK: - TandemPumpDelegate Conformance
@available(macOS 13.0, iOS 14.0, *)
extension TandemPumpManager: TandemPumpDelegate {
    public func tandemPump(_ pump: TandemPump,
                          shouldConnect peripheral: CBPeripheral,
                          advertisementData: [String: Any]?) -> Bool {
        // TODO: Add filtering logic if needed (e.g., check peripheral name)
        return true
    }

    public func tandemPump(_ pump: TandemPump,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        // Create and store the transport
        let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
        activePeripheralManager = peripheralManager
        pumpComm.manager = peripheralManager
        notificationRouter.start(with: peripheralManager, session: pumpComm.getSession())
        updateTransport(transport)
    }
}

// MARK: - PumpCommDelegate Conformance
@available(macOS 13.0, iOS 14.0, *)
extension TandemPumpManager: PumpCommDelegate {
    public func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState) {
        // Update the stored state when pump state changes (e.g., after pairing)
        var currentState = lockedState.value
        currentState.pumpState = pumpState
        lockedState.value = currentState

        updatePairingArtifacts(with: pumpState)

        notifyPumpManagerDelegateDidUpdateState()

        // The state change will be automatically persisted by Loop/Trio
        // when it calls rawState during the next cycle
    }

    public func pumpComm(_ pumpComms: PumpComm,
                         didReceive message: Message,
                         metadata: MessageMetadata?,
                         characteristic: CharacteristicUUID,
                         txId: UInt8) {
        notificationLogger.debug("[notification] Received \(String(describing: type(of: message))) opCode=\(metadata?.opCode ?? type(of: message).props.opCode) characteristic=\(characteristic.prettyName) txId=\(txId)")

        switch message {
        case let battery as CurrentBatteryAbstractResponse:
            handleBatteryResponse(battery, source: .notification)
        case let insulin as InsulinStatusResponse:
            handleReservoirResponse(insulin, source: .notification)
        case let basal as CurrentBasalStatusResponse:
            handleBasalResponse(basal, source: .notification)
        case let bolus as CurrentBolusStatusResponse:
            handleBolusResponse(bolus, source: .notification)
        default:
            if let meta = metadata {
                notificationLogger.debug("[notification] Ignoring \(meta.name) on \(characteristic.prettyName)")
            } else {
                notificationLogger.debug("[notification] Ignoring message type=\(String(describing: type(of: message)))")
            }
        }
    }

    public func pumpComm(_ pumpComms: PumpComm, didEncounterFault event: PumpCommFaultEvent) {
        telemetryLogger.error("Pump fault code=\(event.rawCode) category=\(event.category) attempt=\(event.attempt) willRetry=\(event.willRetry)")

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
        case .tempBasal(let dose):
            if let quantity = dose.scheduledBasalRate {
                return quantity.doubleValue(for: HKUnit.internationalUnitPerHour())
            }
            return dose.value
        default:
            return nil
        }
    }
}
