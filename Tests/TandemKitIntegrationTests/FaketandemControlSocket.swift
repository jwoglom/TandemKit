import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The pieces of faketandem's control surface that only exist as websocket commands
/// (main.go `configureWebsocketCommands`): the pairing code, the cached JPAKE long-term key and a
/// pump-side disconnect. Also records every event the emulator pushes, which is its BLE traffic and
/// connection changes as seen from the pump.
///
/// One socket is held open for the life of the test process: the server keeps a single client
/// reference and clears it whenever *any* socket closes, so a socket opened per test races the
/// previous test's close and the replies go nowhere.
final class FaketandemControlSocket {
    private static let sharedLock = NSLock()
    private static var shared: [URL: FaketandemControlSocket] = [:]

    static func shared(apiBaseURL: URL) throws -> FaketandemControlSocket {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let existing = shared[apiBaseURL] {
            return existing
        }
        let created = FaketandemControlSocket(apiBaseURL: apiBaseURL)
        try created.open()
        shared[apiBaseURL] = created
        return created
    }

    struct Event {
        let raw: [String: Any]
        var type: String? { raw["type"] as? String }
        var characteristic: String? { raw["characteristic"] as? String }
        var data: Data? { (raw["data"] as? String).flatMap { Data(hexadecimalString: $0) } }
        /// The state message the server sends on connect and after `disconnectPump`.
        var connected: Bool? { type == nil ? raw["connected"] as? Bool : nil }
    }

    struct PairingStatus: Equatable {
        let pairingCode: String
        let authenticated: Bool
        let longTermKey: Data?
    }

    private let url: URL
    #if canImport(ObjectiveC)
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    #else
    private var task: LinuxWebSocket?
    #endif
    private let lock = NSLock()
    private var _events: [Event] = []
    private var failure: Error?
    private let commandTimeout: TimeInterval

    init(apiBaseURL: URL, commandTimeout: TimeInterval = 10) {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        url = components.url!
        #if canImport(ObjectiveC)
        session = URLSession(configuration: .ephemeral)
        #endif
        self.commandTimeout = commandTimeout
    }

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    /// Index to remember before an action, so `events(after:)` shows only what the action caused.
    var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _events.count
    }

    func events(after index: Int) -> [Event] {
        Array(events.dropFirst(index))
    }

    func open() throws {
        guard task == nil else { return }
        #if canImport(ObjectiveC)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNext(on: task)
        #else
        let task = LinuxWebSocket(url: url)
        self.task = task
        try task.connect(onText: { [weak self] in self?.record($0) }, onFailure: { [weak self] in self?.fail($0) })
        #endif
        // The server greets with a state message; its arrival proves the socket is up.
        _ = try waitForEvent("websocket greeting", after: 0) { $0.connected != nil }
    }

    func close() {
        #if canImport(ObjectiveC)
        task?.cancel(with: .normalClosure, reason: nil)
        #else
        task?.close()
        #endif
        task = nil
    }

    #if canImport(ObjectiveC)
    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                switch message {
                case let .string(string): self.record(string)
                case let .data(data): self.record(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                self.receiveNext(on: task)
            case let .failure(error):
                self.fail(error)
            }
        }
    }
    #endif

    private func record(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        lock.lock()
        _events.append(Event(raw: object))
        lock.unlock()
    }

    private func fail(_ error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    private func send(command: String, _ params: [String: Any] = [:]) throws {
        guard let task else {
            throw FaketandemClientError.transport("websocket not open")
        }
        var message = params
        message["command"] = command
        let text = String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
        #if canImport(ObjectiveC)
        let box = ResultBox<Error?>()
        task.send(.string(text)) { box.set($0) }
        if let error = try box.wait("websocket send \(command)", timeout: commandTimeout) {
            throw FaketandemClientError.transport("websocket send \(command): \(error)")
        }
        #else
        do {
            try task.send(text)
        } catch {
            throw FaketandemClientError.transport("websocket send \(command): \(error)")
        }
        #endif
    }

    private func waitForEvent(
        _ what: String,
        after index: Int,
        where predicate: @escaping (Event) -> Bool
    ) throws -> Event {
        try IntegrationWait.value(what, timeout: commandTimeout) {
            lock.lock()
            let failure = self.failure
            let candidates = Array(_events.dropFirst(index))
            lock.unlock()
            if let failure {
                throw FaketandemClientError.transport("websocket failed: \(failure)")
            }
            return candidates.first(where: predicate)
        }
    }

    private func pairingStatus(from event: Event) -> PairingStatus {
        PairingStatus(
            pairingCode: event.raw["pairing_code"] as? String ?? "",
            authenticated: event.raw["authenticated"] as? Bool ?? false,
            longTermKey: (event.raw["long_term_key"] as? String).flatMap { $0.isEmpty ? nil : Data(hexadecimalString: $0) }
        )
    }

    private func pairingCommand(_ command: String, _ params: [String: Any] = [:]) throws -> PairingStatus {
        let index = eventCount
        try send(command: command, params)
        let event = try waitForEvent("pairing_state after \(command)", after: index) { $0.type == "pairing_state" }
        return pairingStatus(from: event)
    }

    // MARK: - Commands

    /// Also clears the pump's authentication and its cached long-term key (state.SetPairingCode).
    func setPairingCode(_ code: String) throws -> PairingStatus {
        try pairingCommand("setPairingCode", ["pairingCode": code])
    }

    func pairingStatus() throws -> PairingStatus {
        try pairingCommand("getPairingState")
    }

    func resetLongTermKey() throws -> PairingStatus {
        try pairingCommand("resetLongTermKey")
    }

    func setLongTermKey(_ key: Data) throws -> PairingStatus {
        try pairingCommand("setLongTermKey", ["longTermKey": key.hexadecimalString])
    }

    /// Clears the per-connection session key; the long-term key survives (main.go `resetPairing`).
    func resetAuthentication() throws -> PairingStatus {
        try pairingCommand("resetPairing")
    }

    /// The pump drops the link (`ShutdownConnection`). Returns once the server has reported state.
    func disconnectPump() throws {
        let index = eventCount
        try send(command: "disconnectPump")
        _ = try waitForEvent("state after disconnectPump", after: index) { $0.connected != nil }
    }
}
