//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import LoopKit
import TandemCore
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

        // Note: These delegate assignments will need to be fixed once the actual types are available
        // self.tandemPump.delegate = self
        // self.pumpComm.delegate = self
    }

    public required init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else {
            return nil
        }

        self.lockedState = Locked(state)
        self.tandemPump = TandemPump(state.pumpState)

        // Note: These delegate assignments will need to be fixed once the actual types are available
        // self.tandemPump.delegate = self
        // self.pumpComm.delegate = self
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
        // TODO: Implement pump connection
        print("TandemPumpManager: connect() called")
    }

    public func disconnect() {
        // TODO: Implement pump disconnection
        print("TandemPumpManager: disconnect() called")
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
