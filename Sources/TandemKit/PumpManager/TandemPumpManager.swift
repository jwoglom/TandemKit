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
    private let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    private let tandemPump: TandemPump

    // Status tracking
    private let statusObservers = Locked<[UUID: (observer: PumpManagerStatusObserver, queue: DispatchQueue)]>([:])
    private let lockedStatus: Locked<PumpManagerStatus>

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
            bolusState: .noBolus,
            insulinType: nil,
            deliveryIsUncertain: false
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

    // MARK: - Basic Pump Manager Interface

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get {
            return pumpDelegate.value
        }
        set {
            pumpDelegate.value = newValue
        }
    }

    public func connect() {
        tandemPump.startScanning()
    }

    public func disconnect() {
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
        // Update status to show bolus is initiating
        updateStatus { status in
            status.bolusState = .initiating
        }

        // TODO: Implement actual bolus delivery via pump messages
        delegateQueue.async {
            completion(.communication(PumpCommError.notImplemented))
        }
    }

    public func cancelBolus(completion: @escaping (_ result: PumpManagerResult<DoseEntry?>) -> Void) {
        // Update status to show bolus is being canceled
        updateStatus { status in
            status.bolusState = .canceling
        }

        // TODO: Implement actual bolus cancellation via pump messages
        // For now, return an error indicating this is not yet implemented
        delegateQueue.async {
            completion(.failure(.communication(PumpCommError.notImplemented)))
        }
    }

    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (_ error: PumpManagerError?) -> Void) {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(duration)
        _ = DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: unitsPerHour,
            unit: .unitsPerHour,
            deliveredUnits: nil,
            syncIdentifier: UUID().uuidString
        )

        // Update status to show temp basal is initiating
        updateStatus { status in
            status.basalDeliveryState = .initiatingTempBasal
        }

        // TODO: Implement actual temp basal delivery via pump messages
        // For now, return an error indicating this is not yet implemented
        delegateQueue.async {
            completion(.communication(PumpCommError.notImplemented))
        }
    }

    // MARK: - Delivery Control Methods

    public func suspendDelivery(completion: @escaping (_ error: Error?) -> Void) {
        // Update status to show suspension is in progress
        updateStatus { status in
            status.basalDeliveryState = .suspending
        }

        // TODO: Implement actual delivery suspension via pump messages
        // For now, return an error indicating this is not yet implemented
        delegateQueue.async {
            completion(PumpManagerError.communication(PumpCommError.notImplemented))
        }
    }

    public func resumeDelivery(completion: @escaping (_ error: Error?) -> Void) {
        // Update status to show resume is in progress
        updateStatus { status in
            status.basalDeliveryState = .resuming
        }

        // TODO: Implement actual delivery resumption via pump messages
        // For now, return an error indicating this is not yet implemented
        delegateQueue.async {
            completion(PumpManagerError.communication(PumpCommError.notImplemented))
        }
    }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void) {
        // TODO: Implement basal schedule synchronization with the pump.
        delegateQueue.async {
            completion(.failure(PumpManagerError.communication(PumpCommError.notImplemented)))
        }
    }

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (_ result: Result<DeliveryLimits, Error>) -> Void) {
        // TODO: Implement delivery limit synchronization with the pump.
        delegateQueue.async {
            completion(.failure(PumpManagerError.communication(PumpCommError.notImplemented)))
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

        // The state change will be automatically persisted by Loop/Trio
        // when it calls rawState during the next cycle
    }
}
