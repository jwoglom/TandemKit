import CoreBluetooth
import Foundation
@testable import TandemKit

/// In-memory stand-in for `TandemBluetoothManager`.
///
/// Responses are registered per request type, either as a fixed reply or as a FIFO queue when a
/// test needs the same request answered differently on successive calls. Every message written is
/// recorded in `sentMessages` so a test can assert on the command sequence the driver produced.
///
/// `ensureConnected` runs its completion synchronously on the caller's thread, which keeps the
/// driver's blocking write sequences inline and makes the tests deterministic. Production
/// serializes them onto a command queue instead.
final class StubPumpBluetooth: PumpBluetoothConnection {
    /// Set to make `ensureConnected` report a failure instead of running the command job.
    var connectError: Error?
    /// Invoked for every write, before the canned response is looked up.
    var onWrite: ((Message) -> Void)?

    weak var pumpManager: TandemPumpManager?
    var manager: CBCentralManager? { nil }

    private(set) var sentMessages: [Message] = []
    private(set) var ensureConnectedCount = 0
    private(set) var disconnectCount = 0
    private(set) var deactivateCount = 0
    private(set) var unhandledRequests: [Message] = []

    private var fixedResponses: [ObjectIdentifier: (Message) -> Message?] = [:]
    private var queuedResponses: [ObjectIdentifier: [(Message) -> Message?]] = [:]
    private let lock = NSLock()

    // MARK: - Stub registration

    /// Answers every `requestType` write with `response`.
    func stub(_ requestType: Message.Type, with response: Message) {
        stub(requestType) { _ in response }
    }

    /// Answers every `requestType` write by calling `handler` with the request that was sent.
    /// Returning nil simulates a request the pump never answered.
    func stub(_ requestType: Message.Type, handler: @escaping (Message) -> Message?) {
        lock.lock()
        fixedResponses[ObjectIdentifier(requestType)] = handler
        lock.unlock()
    }

    /// Answers successive `requestType` writes with `responses` in order. Once the queue is drained
    /// the fixed stub for that type (if any) takes over.
    func enqueue(_ requestType: Message.Type, responses: [Message?]) {
        let handlers: [(Message) -> Message?] = responses.map { response in
            { _ in response }
        }
        lock.lock()
        queuedResponses[ObjectIdentifier(requestType), default: []] += handlers
        lock.unlock()
    }

    // MARK: - Assertions

    func sent<T: Message>(_ type: T.Type) -> [T] {
        lock.lock()
        defer { lock.unlock() }
        return sentMessages.compactMap { $0 as? T }
    }

    func didSend(_ type: Message.Type) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sentMessages.contains { Swift.type(of: $0) == type }
    }

    // MARK: - PumpBluetoothConnection

    func startScan(_: @escaping (_ result: TandemPumpScan) -> Void) -> Bool { false }

    func stopScan() {}

    func connect(_: CBPeripheral, completion: @escaping (Error?) -> Void) {
        completion(connectError)
    }

    func ensureConnected(completion: @escaping (Error?) -> Void) {
        lock.lock()
        ensureConnectedCount += 1
        let error = connectError
        lock.unlock()
        completion(error)
    }

    func write<R: PumpRequest>(_ request: R, maxChunkSize _: Int?) -> R.Response? {
        respond(to: request) as? R.Response
    }

    func writeUntyped(_ message: any Message, expecting _: any Message.Type, maxChunkSize _: Int?) -> (any Message)? {
        respond(to: message)
    }

    private func respond(to message: any Message) -> (any Message)? {
        onWrite?(message)

        lock.lock()
        sentMessages.append(message)
        let key = ObjectIdentifier(type(of: message))

        var handler: ((Message) -> Message?)?
        if var queue = queuedResponses[key], !queue.isEmpty {
            handler = queue.removeFirst()
            queuedResponses[key] = queue
        } else {
            handler = fixedResponses[key]
        }

        if handler == nil {
            unhandledRequests.append(message)
        }
        lock.unlock()

        return handler?(message)
    }

    func disconnect() {
        lock.lock()
        disconnectCount += 1
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        deactivateCount += 1
        lock.unlock()
        disconnect()
        pumpManager = nil
    }
}
