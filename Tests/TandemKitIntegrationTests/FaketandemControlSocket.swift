import Foundation

/// The pieces of faketandem's control surface that only exist as websocket commands
/// (main.go `configureWebsocketCommands`): the pairing code, the cached JPAKE long-term key and a
/// pump-side disconnect. Also records every event the emulator pushes, which is its BLE traffic and
/// connection changes as seen from the pump.
///
/// One socket is held open for the life of the harness: the server keeps a single client
/// reference and clears it whenever any socket closes, so opening one per command would race the
/// replies.
final class FaketandemControlSocket {
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
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var _events: [Event] = []
    private var failure: Error?
    private let commandTimeout: TimeInterval

    init(apiBaseURL: URL, commandTimeout: TimeInterval = 10) {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        url = components.url!
        session = URLSession(configuration: .ephemeral)
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
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNext(on: task)
        // The server greets with a state message; its arrival proves the socket is up.
        _ = try waitForEvent("websocket greeting", after: 0) { $0.connected != nil }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                var text: String?
                switch message {
                case let .string(string): text = string
                case let .data(data): text = String(data: data, encoding: .utf8)
                @unknown default: break
                }
                if let text, let data = text.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    self.lock.lock()
                    self._events.append(Event(raw: object))
                    self.lock.unlock()
                }
                self.receiveNext(on: task)
            case let .failure(error):
                self.lock.lock()
                self.failure = error
                self.lock.unlock()
            }
        }
    }

    private func send(command: String, _ params: [String: Any] = [:]) throws {
        guard let task else {
            throw FaketandemClientError.transport("websocket not open")
        }
        var message = params
        message["command"] = command
        let data = try JSONSerialization.data(withJSONObject: message)
        let box = ResultBox<Error?>()
        task.send(.string(String(decoding: data, as: UTF8.self))) { box.set($0) }
        if let error = try box.wait("websocket send \(command)", timeout: commandTimeout) {
            throw FaketandemClientError.transport("websocket send \(command): \(error)")
        }
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
