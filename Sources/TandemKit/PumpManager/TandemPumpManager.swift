//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import CoreBluetooth
import HealthKit
import LoopKit
import TandemCore
import TandemBLE
#if canImport(UIKit)
import UIKit
#endif

// Simple delegate wrapper
private class WeakSynchronizedDelegate<T> {
    private var _value: T?
    var _queue: DispatchQueue = DispatchQueue.main

    var value: T? {
        get {
            return _queue.sync { _value }
        }
        set {
            _queue.sync { _value = newValue }
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

    public typealias RawStateValue = [String: Any]

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let dosingDelegate = WeakSynchronizedDelegate<PumpManagerDosingDecisionDelegate>()
    private let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    private let tandemPump: TandemPump
    private let log = OSLog(category: "TandemPumpManager")

    // Status tracking
    private let statusObservers = Locked<[UUID: (observer: PumpManagerStatusObserver, queue: DispatchQueue)]>([:])
    private let lockedStatus: Locked<PumpManagerStatus>
    private let activeBolus = Locked<ActiveBolus?>(nil)
    private let activeTempBasal = Locked<ActiveTempBasal?>(nil)
    private let lastScheduledBasalRate = Locked<Double?>(nil)

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
            bolusState: .none
        )
    }

    public init(state: TandemPumpManagerState) {
        self.lockedState = Locked(state)
        self.lockedStatus = Locked(Self.makeDefaultStatus())
        self.tandemPump = TandemPump(state.pumpState)

        self.tandemPump.delegate = self
        self.pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
    }

    public required init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else {
            return nil
        }

        self.lockedState = Locked(state)
        self.lockedStatus = Locked(Self.makeDefaultStatus())
        self.tandemPump = TandemPump(state.pumpState)

        self.tandemPump.delegate = self
        self.pumpComm.delegate = self
        updatePairingArtifacts(with: state.pumpState)
    }

    public var rawState: RawStateValue {
        return lockedState.value.rawValue
    }

    public var debugDescription: String {
        return "TandemPumpManager(state: \(lockedState.value))"
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

    public var lastReconciliation: Date? {
        return lockedState.value.lastReconciliation
    }

    public var status: PumpManagerStatus {
        return lockedStatus.value
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
        notifyStatusObservers(oldStatus: oldStatus, newStatus: newStatus)
    }

    private func currentTransport() -> PumpMessageTransport? {
        return transportLock.value
    }

    private func notifyPumpManagerDelegateOfError(_ error: PumpCommError) {
        guard let delegate = pumpManagerDelegate else { return }
        delegateQueue.async {
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
        guard let delegate = pumpManagerDelegate else { return }
        delegateQueue.async {
            delegate.pumpManagerDidUpdateState(self)
        }
    }

    private func completeBolus(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerResult<DoseEntry>) -> Void) {
        delegateQueue.async {
            completion(result)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didEnactBolus: result)
            }
        }
    }

    private func completeCancelBolus(_ result: PumpManagerResult<DoseEntry?>, completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        delegateQueue.async {
            completion(result)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didCancelBolus: result)
            }
        }
    }

    private func completeTempBasal(_ result: PumpManagerResult<DoseEntry>, completion: @escaping (PumpManagerResult<DoseEntry>) -> Void) {
        delegateQueue.async {
            completion(result)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didEnactTempBasal: result)
            }
        }
    }

    private func completeSuspend(_ error: Error?, completion: @escaping (Error?) -> Void) {
        delegateQueue.async {
            completion(error)
            if let delegate = self.dosingDelegate.value {
                delegate.pumpManager(self, didSuspendDeliveryWithError: error)
            }
        }
    }

    private func completeResume(_ error: Error?, completion: @escaping (Error?) -> Void) {
        delegateQueue.async {
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

        if let statusRate = lockedStatus.value.basalDeliveryState.scheduledBasalRateValue, statusRate > 0 {
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
        tandemPump.startScanning()
    }

    public func disconnect() {
        tandemPump.disconnect()
    }

    // MARK: - PumpManager Additional Methods

    public func assertCurrentPumpData() {
        // Request the pump to send current data
        // This will be implemented when we have message handling for pump data queries
        // For now, this is a no-op as data is pushed from the pump
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

    public func enactBolus(units: Double, at startDate: Date, willRequest: @escaping (_ dose: DoseEntry) -> Void, completion: @escaping (_ result: PumpManagerResult<DoseEntry>) -> Void) {
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: nil,
            value: units,
            unit: .units,
            deliveredUnits: nil,
            syncIdentifier: UUID().uuidString
        )

        willRequest(dose)

        updateStatus { status in
            status.bolusState = .initiating
        }

        guard units > 0 else {
            updateStatus { status in
                status.bolusState = .none
            }
            let error = PumpCommError.other
            notifyPumpManagerDelegateOfError(error)
            completeBolus(.failure(error), completion: completion)
            return
        }

        guard let transport = currentTransport() else {
            updateStatus { status in
                status.bolusState = .none
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeBolus(.failure(error), completion: completion)
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
                    status.bolusState = .none
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeBolus(.failure(pumpError), completion: completion)
            }
        }
    }

    public func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void) {
        updateStatus { status in
            status.bolusState = .canceling
        }

        guard let transport = currentTransport() else {
            updateStatus { status in
                status.bolusState = .none
            }
            let error = PumpCommError.pumpNotConnected
            notifyPumpManagerDelegateOfError(error)
            completeCancelBolus(.failure(error), completion: completion)
            return
        }

        guard let active = activeBolus.value else {
            updateStatus { status in
                status.bolusState = .none
            }
            let error = PumpCommError.other
            notifyPumpManagerDelegateOfError(error)
            completeCancelBolus(.failure(error), completion: completion)
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
                    status.bolusState = .none
                }

                self.recordReconciliation(at: endDate)
                self.completeCancelBolus(.success(canceledDose), completion: completion)
            } catch {
                let pumpError = error as? PumpCommError ?? PumpCommError.other
                self.updateStatus { status in
                    status.bolusState = .inProgress(active.dose)
                }
                self.notifyPumpManagerDelegateOfError(pumpError)
                self.completeCancelBolus(.failure(pumpError), completion: completion)
            }
        }
    }

    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (_ result: PumpManagerResult<DoseEntry>) -> Void) {
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
            completeTempBasal(.failure(error), completion: completion)
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
                self.completeTempBasal(.failure(pumpError), completion: completion)
            }
        }
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
                    status.bolusState = .none
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
}

private extension TandemPumpManager {
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
