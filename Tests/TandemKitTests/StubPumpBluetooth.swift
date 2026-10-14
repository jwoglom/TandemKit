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
/// serializes them onto a command queue instead, so a job queued from inside another one runs
/// once that one returns, here as there.
final class StubPumpBluetooth: PumpBluetoothConnection {
    /// Set to make `ensureConnected` report a failure instead of running the command job.
    var connectError: Error?
    /// Invoked for every write, before the canned response is looked up.
    var onWrite: ((Message) -> Void)?

    weak var pumpManager: TandemPumpManager?
    var manager: CBCentralManager? { nil }
    /// Defaults to a working radio, so a test that says nothing about Bluetooth exercises the link.
    var bluetoothState: CBManagerState = .poweredOn
    var isJpakeFailureLimitReached = false

    private(set) var sentMessages: [Message] = []
    private(set) var responseCount = 0
    private(set) var ensureConnectedCount = 0
    private(set) var disconnectCount = 0
    private(set) var deactivateCount = 0
    private(set) var unhandledRequests: [Message] = []

    private var jobThread: Thread?
    private var queuedJobs: [() -> Void] = []

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

    /// A pump running `profileMilliunits` whose basal status follows the temp rates it is sent,
    /// applying each percent to its own profile as a pump does.
    /// `capMilliunits` limits the temp rate, as the pump's max basal limit does.
    func stubBasalPump(
        profileMilliunits: UInt32,
        runningTempPercent: Int? = nil,
        capMilliunits: UInt32? = nil,
        tempRateId: Int = 42
    ) {
        let pump = StubBasalPump(
            profileMilliunits: profileMilliunits,
            tempPercent: runningTempPercent,
            capMilliunits: capMilliunits
        )
        stub(SetTempRateRequest.self) { request in
            pump.setTempPercent((request as? SetTempRateRequest)?.percent)
            return SetTempRateResponse(status: 0, tempRateId: tempRateId)
        }
        stub(StopTempRateRequest.self) { _ in
            pump.setTempPercent(nil)
            return StopTempRateResponse(status: 0, tempRateId: tempRateId)
        }
        stub(CurrentBasalStatusRequest.self) { _ in pump.status() }
    }

    /// Answers the delivery reads a sync needs before it moves `lastReconciliation`: no bolus, and
    /// the profile's basal at `profileMilliunits` per hour.
    func stubIdleDelivery(profileMilliunits: UInt32 = 1000) {
        stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
        stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: profileMilliunits,
            currentBasalRate: profileMilliunits,
            basalModifiedBitmask: 0
        ))
    }

    // MARK: - Assertions

    /// Forget the traffic recorded so far, so a later phase of a test can assert on its own
    /// messages alone. Registered stubs and `onWrite` are left in place.
    func resetRecordedTraffic() {
        lock.lock()
        sentMessages = []
        unhandledRequests = []
        ensureConnectedCount = 0
        disconnectCount = 0
        lock.unlock()
    }

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

    /// Set to hold `connect`'s completion in `heldConnectCompletion` for the test to call, as a real
    /// attempt's arrives later.
    var holdsConnectCompletion = false
    private(set) var heldConnectCompletion: ((Error?) -> Void)?

    func connect(_: CBPeripheral, completion: @escaping (Error?) -> Void) {
        guard !holdsConnectCompletion else {
            heldConnectCompletion = completion
            return
        }
        completion(connectError)
    }

    func ensureConnected(completion: @escaping (Error?) -> Void) {
        lock.lock()
        ensureConnectedCount += 1
        let error = connectError
        if jobThread == Thread.current {
            queuedJobs.append { completion(error) }
            lock.unlock()
            return
        }
        let outermost = jobThread == nil
        if outermost {
            jobThread = Thread.current
        }
        lock.unlock()

        completion(error)

        guard outermost else {
            return
        }
        while true {
            lock.lock()
            guard !queuedJobs.isEmpty else {
                jobThread = nil
                lock.unlock()
                return
            }
            let job = queuedJobs.removeFirst()
            lock.unlock()
            job()
        }
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

        let response = handler?(message)
        if response != nil {
            lock.lock()
            responseCount += 1
            lock.unlock()
        }
        return response
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

private final class StubBasalPump {
    private let lock = NSLock()
    private let profileMilliunits: UInt32
    private let capMilliunits: UInt32?
    private var tempPercent: Int?

    init(profileMilliunits: UInt32, tempPercent: Int?, capMilliunits: UInt32?) {
        self.profileMilliunits = profileMilliunits
        self.tempPercent = tempPercent
        self.capMilliunits = capMilliunits
    }

    func setTempPercent(_ percent: Int?) {
        lock.lock()
        tempPercent = percent
        lock.unlock()
    }

    func status() -> CurrentBasalStatusResponse {
        lock.lock()
        defer { lock.unlock() }
        guard let tempPercent else {
            return CurrentBasalStatusResponse(
                profileBasalRate: profileMilliunits,
                currentBasalRate: profileMilliunits,
                basalModifiedBitmask: 0
            )
        }
        return CurrentBasalStatusResponse(
            profileBasalRate: profileMilliunits,
            currentBasalRate: min(profileMilliunits * UInt32(tempPercent) / 100, capMilliunits ?? .max),
            basalModifiedBitmask: 0x02
        )
    }
}
