//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import CoreBluetooth
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

public class TandemPumpManager: PumpManager {
    public static var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"

    public typealias RawStateValue = [String: Any]

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let lockedState: Locked<TandemPumpManagerState>
    private let transportLock = Locked<PumpMessageTransport?>(nil)
    private let tandemPump: TandemPump

    private func updatePairingArtifacts(with pumpState: PumpState?) {
#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
        let derivedSecret = pumpState?.derivedSecret
        let serverNonce = pumpState?.serverNonce
        Task { @MainActor in
            PumpStateSupplier.storePairingArtifacts(derivedSecret: derivedSecret, serverNonce: serverNonce)
        }
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

    public init(state: TandemPumpManagerState) {
        self.lockedState = Locked(state)
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
        // TODO: Call bluetoothManager.permanentDisconnect() through tandemPump
        print("TandemPumpManager: disconnect() - not yet fully implemented")
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
}

extension TandemPumpManager: PumpManagerUI {
#if canImport(UIKit)
    public func pairingViewController(onFinished: @escaping (Result<Void, Error>) -> Void) -> UIViewController {
        return TandemPumpPairingViewController(pumpManager: self, completion: onFinished)
    }
#endif
}

// MARK: - TandemPumpDelegate Conformance
extension TandemPumpManager: TandemPumpDelegate {
    public func tandemPump(_ pump: TandemPump,
                          shouldConnect peripheral: CBPeripheral,
                          advertisementData: [String: Any]?) -> Bool {
        // TODO: Add filtering logic if needed (e.g., check peripheral name)
        return true
    }

    @MainActor
    public func tandemPump(_ pump: TandemPump,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        // Create and store the transport
        let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
        updateTransport(transport)
    }
}

// MARK: - PumpCommDelegate Conformance
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
