#if TANDEMKIT_VIRTUAL_PUMP
import Foundation
import LoopKit

/// A test's handle on the driver inside a host app (Trio in the simulator), over a socket on
/// 127.0.0.1. The test makes the calls the host and its onboarding screens make, the host's own
/// delegate receives what the driver reports, and the test reads back every batch it was sent and
/// when the host finished with it. Only in the virtual pump build, whose Bluetooth is faketandem's
/// socket, so nothing sent here can reach a real pump.
///
/// One JSON `Request` per line, answered by one `Response` line, in order, per connection.
enum VirtualPumpControl {
    /// The loopback port to listen on, read from the host app's environment.
    static let environmentVariable = "TANDEMKIT_VIRTUAL_PUMP_CONTROL"

    static var port: UInt16? = ProcessInfo.processInfo.environment[environmentVariable].flatMap { UInt16($0) }

    private static let logger = TandemLogger(category: "VirtualPumpControl")
    private static let lock = NSLock()
    private static weak var latestManager: TandemPumpManager?
    private static var server: Server?
    private static var logs: [ObjectIdentifier: [Batch]] = [:]
    /// Per manager; a test reads a few dozen.
    private static let maximumLoggedBatches = 1000

    // MARK: - Hooks in TandemPumpManager

    /// The host's latest manager is the one commands reach. Starts listening on the first call when
    /// the environment names a port.
    static func attach(_ manager: TandemPumpManager) {
        lock.lock()
        defer { lock.unlock() }
        latestManager = manager
        logs[ObjectIdentifier(manager)] = []
        guard server == nil, let port else {
            return
        }
        do {
            server = try Server(port: port) {
                lock.lock()
                defer { lock.unlock() }
                return latestManager
            }
            logger.warning("Virtual pump control listening on 127.0.0.1:\(port)")
        } catch {
            logger.error("Virtual pump control could not listen on 127.0.0.1:\(port): \(error)")
        }
    }

    /// Called as a batch goes to the delegate; returns the index `delegateDidFinish` takes.
    static func willDeliver(
        _ events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        hostNow: Date,
        from manager: TandemPumpManager
    ) -> Int {
        let batch = Batch(
            index: 0,
            hostNow: hostNow,
            lastReconciliation: lastReconciliation,
            replacePendingEvents: replacePendingEvents,
            events: events.map(Event.init),
            completed: false,
            delegateError: nil
        )
        lock.lock()
        defer { lock.unlock() }
        var log = logs[ObjectIdentifier(manager)] ?? []
        let index = (log.last?.index ?? -1) + 1
        log.append(Batch(copying: batch, index: index))
        if log.count > maximumLoggedBatches {
            log.removeFirst(log.count - maximumLoggedBatches)
        }
        logs[ObjectIdentifier(manager)] = log
        return index
    }

    /// The host's completion for batch `index`.
    static func delegateDidFinish(_ index: Int, error: Error?, from manager: TandemPumpManager) {
        lock.lock()
        defer { lock.unlock() }
        guard var log = logs[ObjectIdentifier(manager)],
              let position = log.firstIndex(where: { $0.index == index })
        else {
            return
        }
        log[position].completed = true
        log[position].delegateError = error.map { String(describing: $0) }
        logs[ObjectIdentifier(manager)] = log
    }

    static func batches(of manager: TandemPumpManager, after index: Int?) -> [Batch] {
        lock.lock()
        defer { lock.unlock() }
        return (logs[ObjectIdentifier(manager)] ?? []).filter { $0.index > (index ?? -1) }
    }

    // MARK: - Wire format

    struct Request: Codable, Equatable {
        enum Command: String, Codable {
            /// Nothing else; answers with `status`.
            case status
            /// Scan, then `pairPump(code:peripheral:)` with the first pump seen, as the scan screen
            /// does. With `longTermKey` (hex), the driver takes that key as a completed pairing's
            /// first, so only the quick-reconnect rounds run; the test gives faketandem the same one.
            case pair
            /// `enactBolus(units:activationType:)`, `automatic` choosing the activation type.
            case bolus
            /// `syncPumpData`, as a pull to refresh does; answers with `lastSync`.
            case sync
            /// Every batch sent to the delegate after index `after`.
            case pumpEventBatches
        }

        var id: Int = 0
        var command: Command
        var code: String?
        var longTermKey: String?
        var units: Double?
        var automatic: Bool?
        var after: Int?
    }

    struct Response: Codable, Equatable {
        var id: Int
        var error: String?
        var status: Status?
        var lastSync: Date?
        var batches: [Batch]?
    }

    struct Status: Codable, Equatable {
        var onboarded: Bool
        var connected: Bool
        var delegateAttached: Bool
    }

    struct Batch: Codable, Equatable {
        var index: Int
        /// The driver's clock when the batch went out.
        var hostNow: Date
        var lastReconciliation: Date?
        var replacePendingEvents: Bool
        var events: [Event]
        /// The host called the completion; until then it may still be storing the batch.
        var completed: Bool
        var delegateError: String?

        init(
            index: Int,
            hostNow: Date,
            lastReconciliation: Date?,
            replacePendingEvents: Bool,
            events: [Event],
            completed: Bool,
            delegateError: String?
        ) {
            self.index = index
            self.hostNow = hostNow
            self.lastReconciliation = lastReconciliation
            self.replacePendingEvents = replacePendingEvents
            self.events = events
            self.completed = completed
            self.delegateError = delegateError
        }

        fileprivate init(copying batch: Batch, index: Int) {
            self = batch
            self.index = index
        }

        var pumpEvents: [NewPumpEvent] {
            events.map(\.pumpEvent)
        }
    }

    /// LoopKit's `NewPumpEvent` is not `Codable`; its `DoseEntry` is. The driver gives every event a
    /// dose and lets the dose name its type, so date, raw, title and dose rebuild it exactly.
    struct Event: Codable, Equatable {
        var date: Date
        var raw: Data
        var title: String
        var dose: DoseEntry?

        init(_ event: NewPumpEvent) {
            date = event.date
            raw = event.raw
            title = event.title
            dose = event.dose
        }

        var pumpEvent: NewPumpEvent {
            NewPumpEvent(date: date, dose: dose, raw: raw, title: title)
        }
    }

    // MARK: - Server

    final class Server {
        private let listener: SocketListener
        var port: UInt16 { listener.port }

        init(port: UInt16 = 0, manager: @escaping () -> TandemPumpManager?) throws {
            listener = try SocketListener(port: port, name: "VirtualPumpControl") { link in
                Server.serve(link, manager: manager)
            }
        }

        func stop() {
            listener.stop()
        }

        private static func serve(_ link: SocketLink, manager: () -> TandemPumpManager?) {
            defer { link.close() }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            while let line = try? link.readLine(timeout: nil) {
                let response: Response
                do {
                    let request = try decoder.decode(Request.self, from: line)
                    response = handle(request, manager: manager())
                } catch {
                    response = Response(id: -1, error: "bad request: \(error)")
                }
                guard let data = try? encoder.encode(response), (try? link.send(line: data)) != nil else {
                    return
                }
            }
        }

        static func handle(_ request: Request, manager: TandemPumpManager?) -> Response {
            var response = Response(id: request.id)
            guard let manager else {
                response.error = "no TandemPumpManager has been created"
                return response
            }
            do {
                switch request.command {
                case .status:
                    break
                case .pair:
                    try pair(manager, code: request.code, longTermKey: request.longTermKey)
                case .bolus:
                    try bolus(manager, units: request.units, automatic: request.automatic ?? false)
                case .sync:
                    response.lastSync = try sync(manager)
                case .pumpEventBatches:
                    response.batches = VirtualPumpControl.batches(of: manager, after: request.after)
                }
            } catch {
                response.error = String(describing: error)
            }
            response.status = Status(
                onboarded: manager.isOnboarded,
                connected: manager.state.isConnected,
                delegateAttached: manager.pumpManagerDelegate != nil
            )
            return response
        }

        private static func pair(_ manager: TandemPumpManager, code: String?, longTermKey: String?) throws {
            guard let code else {
                throw ControlError("pair needs a code")
            }
            let key = try longTermKey.map { hex -> Data in
                guard let key = Data(hexadecimalString: hex) else {
                    throw ControlError("longTermKey is not hex")
                }
                return key
            }
            let scan = Completion<TandemPumpScan>()
            // The central reports powered-on asynchronously after it is created.
            let deadline = Date().addingTimeInterval(10)
            while !manager.bluetooth.startScan({ scan.finish($0) }) {
                guard Date() < deadline else {
                    throw ControlError("Bluetooth never powered on")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            let found = try scan.wait("an advertisement", timeout: 30)
            manager.bluetooth.stopScan()
            if let key {
                manager.state.pumpState.derivedSecret = key
                manager.state.pumpState.peripheralUuid = found.peripheral.identifier.uuidString
            }
            let paired = Completion<Error?>()
            manager.pairPump(code: code, peripheral: found.peripheral) { paired.finish($0) }
            if let error = try paired.wait("pairPump", timeout: 90) {
                throw error
            }
        }

        private static func bolus(_ manager: TandemPumpManager, units: Double?, automatic: Bool) throws {
            guard let units else {
                throw ControlError("bolus needs units")
            }
            let enacted = Completion<PumpManagerError?>()
            manager.enactBolus(units: units, activationType: automatic ? .automatic : .manualNoRecommendation) {
                enacted.finish($0)
            }
            if let error = try enacted.wait("enactBolus", timeout: 120) {
                throw error
            }
        }

        private static func sync(_ manager: TandemPumpManager) throws -> Date? {
            let synced = Completion<Date?>()
            manager.syncPumpData { synced.finish($0) }
            return try synced.wait("syncPumpData", timeout: 240)
        }
    }

    /// The test's end: one request at a time, a refusal thrown as `ControlError`.
    final class Client {
        private let link: SocketLink
        private var nextId = 1

        init(port: UInt16) throws {
            link = try SocketLink(connectTo: SocketPumpEndpoint(host: "127.0.0.1", port: port))
        }

        @discardableResult
        func send(_ request: Request, timeout: TimeInterval = 300) throws -> Response {
            var request = request
            request.id = nextId
            nextId += 1
            try link.send(line: JSONEncoder().encode(request))
            guard let line = try link.readLine(timeout: timeout) else {
                throw ControlError("the control channel closed")
            }
            let response = try JSONDecoder().decode(Response.self, from: line)
            if let error = response.error {
                throw ControlError(error)
            }
            return response
        }

        func close() {
            link.shutdown()
            link.close()
        }
    }

    struct ControlError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    /// The first value a callback delivers, waited for on the connection's own thread.
    private final class Completion<Value> {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var value: Value?

        func finish(_ value: Value) {
            lock.lock()
            defer { lock.unlock() }
            guard self.value == nil else {
                return
            }
            self.value = value
            done.signal()
        }

        func wait(_ what: String, timeout: TimeInterval) throws -> Value {
            guard done.wait(timeout: .now() + timeout) == .success else {
                throw ControlError("timed out after \(Int(timeout)) s waiting for \(what)")
            }
            lock.lock()
            defer { lock.unlock() }
            return value!
        }
    }
}

extension VirtualPumpControl.Response {
    init(id: Int, error: String? = nil) {
        self.init(id: id, error: error, status: nil, lastSync: nil, batches: nil)
    }
}
#endif
