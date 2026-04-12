import Dispatch
import Foundation
import LoopKit
import TandemCore

public protocol PumpCommDelegate: AnyObject {
    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState)
    func pumpComm(
        _ pumpComms: PumpComm,
        didReceive message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    )
    func pumpComm(_ pumpComms: PumpComm, didEncounterFault event: PumpCommFaultEvent)
    func pumpComm(_ pumpComms: PumpComm, didReceiveQualifyingEvents events: Set<QualifyingEvent>)
}

public class PumpComm: CustomDebugStringConvertible {
    public weak var delegate: PumpCommDelegate?

    public let log = TandemLogger(category: "PumpComm")

    public var retryPolicy: ExponentialPumpCommRetryPolicy
    private let delayHandler: (TimeInterval) -> Void

    // Serial command queue — only one pump message round-trip at a time
    private let commandQueue = DispatchQueue(label: "com.loopkit.TandemKit.PumpComm.commandQueue", qos: .userInitiated)
    private static let commandQueueKey = DispatchSpecificKey<Bool>()
    private var commandQueueKeyInstalled = false

    /// True when the current thread is already executing on the command queue.
    private var isOnCommandQueue: Bool {
        DispatchQueue.getSpecific(key: PumpComm.commandQueueKey) == true
    }

    private var session: PumpCommSession?

    // Only valid to access on the session serial queue
    private var pumpState: PumpState?

    func syncPumpState(_ pumpState: PumpState?) {
        self.pumpState = pumpState
        let sessionState = pumpState ?? PumpState()
        session?.updateState(sessionState)
    }

    public var isDevicePaired: Bool {
        pumpState?.derivedSecret != nil
    }

    public var isAuthenticated: Bool {
        pumpState?.derivedSecret != nil
    }

    public var pumpPeripheralUuid: String? {
        pumpState?.peripheralUuid
    }

    // TODO(jwoglom): device name or PIN?
    public init(
        pumpState: PumpState?,
        retryPolicy: ExponentialPumpCommRetryPolicy = ExponentialPumpCommRetryPolicy(),
        delayHandler: ((TimeInterval) -> Void)? = nil
    ) {
        delegate = nil
        self.retryPolicy = retryPolicy
        self.delayHandler = delayHandler ?? PumpComm.defaultDelayHandler

        let initialState = pumpState ?? PumpState()
        self.pumpState = pumpState ?? initialState
        session = PumpCommSession(pumpState: initialState, delegate: self)

        commandQueue.setSpecific(key: PumpComm.commandQueueKey, value: true)
        commandQueueKeyInstalled = true
    }

    private static func defaultDelayHandler(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        Thread.sleep(forTimeInterval: interval)
    }

    public func pair(transport: PumpMessageTransport, peripheralUuid: String, pairingCode: String) throws {
        let session = ensureSession()
        log.debug("PumpComm pair started")
        try session.runSynchronously(withName: "Pairing") {
            try session.pair(transport: transport, peripheralUuid: peripheralUuid, pairingCode: pairingCode)
        }
        log.debug("PumpComm pair finished")
    }

    public func confirmAuthentication(
        transport: PumpMessageTransport,
        peripheralUuid: String,
        derivedSecret: Data
    ) throws {
        guard !peripheralUuid.isEmpty, !derivedSecret.isEmpty else {
            throw PumpCommError.missingAuthenticationKey
        }

        let session = ensureSession()
        log.debug("PumpComm confirmAuthentication started")
        try session.runSynchronously(withName: "ConfirmAuthentication") {
            try session.confirmAuthentication(
                transport: transport,
                peripheralUuid: peripheralUuid,
                derivedSecret: derivedSecret
            )
        }
        log.debug("PumpComm confirmAuthentication finished")
    }

    private func ensureSession() -> PumpCommSession {
        if let session = session {
            return session
        }

        let state = pumpState ?? PumpState()
        let newSession = PumpCommSession(pumpState: state, delegate: self)
        session = newSession
        pumpState = state
        return newSession
    }

    func getSession() -> PumpCommSession {
        ensureSession()
    }

    /// Send a message to the pump and receive a response.
    ///
    /// This is a low-level method that sends a message through the transport layer
    /// and returns the response. The transport layer handles packet assembly, HMAC,
    /// CRC, and BLE communication.
    ///
    /// - Parameters:
    ///   - transport: The message transport to use (usually PeripheralManagerTransport)
    ///   - message: The message to send
    /// - Returns: The response message from the pump
    /// - Throws: PumpCommError if communication fails or response is invalid
    public func sendMessage(transport: PumpMessageTransport, message: Message) throws -> Message {
        // If we're already on the command queue (e.g. inside performOnCommandQueue),
        // execute directly to avoid deadlock.
        if isOnCommandQueue {
            return try _sendMessage(transport: transport, message: message)
        }

        // Otherwise, serialize onto the command queue so only one round-trip is in flight.
        var result: Result<Message, Error>!
        commandQueue.sync {
            do {
                result = .success(try _sendMessage(transport: transport, message: message))
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }

    /// The actual send implementation, always called on the command queue.
    private func _sendMessage(transport: PumpMessageTransport, message: Message) throws -> Message {
        log.debug("sendMessage: attempting to send \(message)")

        var attempt = 0

        while true {
            attempt += 1
            do {
                let response = try transport.sendMessage(message)

                if let errorResponse = response as? ErrorResponse {
                    log.error(
                        "sendMessage: pump returned error response (code=\(errorResponse.errorCodeId)) on attempt \(attempt)"
                    )
                    switch handleFault(for: message, response: errorResponse, attempt: attempt) {
                    case .retry:
                        continue
                    case let .fail(event):
                        throw PumpCommError.pumpFault(event: event)
                    }
                }

                return response
            } catch let error as PumpCommError {
                log.error("sendMessage pump communication error: \(error)")
                throw error
            } catch {
                log.error("sendMessage unexpected error: \(error)")
                throw PumpCommError.transportError(underlying: error)
            }
        }
    }

    private enum FaultHandlingResult {
        case retry
        case fail(PumpCommFaultEvent)
    }

    private func handleFault(for message: Message, response: ErrorResponse, attempt: Int) -> FaultHandlingResult {
        let decision = retryPolicy.decision(for: response.errorCode, attempt: attempt)
        let event = PumpCommFaultEvent(
            request: message,
            response: response,
            code: response.errorCode,
            attempt: attempt,
            decision: decision
        )

        delegate?.pumpComm(self, didEncounterFault: event)

        switch decision {
        case let .retry(delay):
            delayHandler(delay)
            return .retry
        case .doNotRetry:
            log.error("sendMessage: not retrying fault code \(response.errorCodeId)")
            return .fail(event)
        }
    }

    /// Send a message and expect a specific response type.
    ///
    /// This is a convenience method that sends a message and automatically casts
    /// the response to the expected type.
    ///
    /// - Parameters:
    ///   - transport: The message transport to use
    ///   - message: The message to send
    ///   - expectedType: The expected response type
    /// - Returns: The response message cast to the expected type
    /// - Throws: PumpCommError if communication fails or response type doesn't match
    public func sendMessage<T: Message>(
        transport: PumpMessageTransport,
        message: Message,
        expecting expectedType: T.Type
    ) throws -> T {
        let response = try sendMessage(transport: transport, message: message)

        guard let typedResponse = response as? T else {
            log.error(
                "sendMessage unexpected response type: expected \(expectedType), got \(type(of: response))"
            )
            throw PumpCommError.unexpectedResponse(
                expected: String("\(type(of: expectedType))"),
                actual: String("\(type(of: response))")
            )
        }

        return typedResponse
    }

    // MARK: - Command Queue

    /// Execute a block on the serial command queue.
    ///
    /// Use this to hold the queue across multi-message sequences (e.g. bolus
    /// permission + initiate, temp basal query + stop + set). Individual
    /// `sendMessage` calls within the block will detect re-entrancy and skip
    /// the queue acquire, so there is no deadlock risk.
    public func performOnCommandQueue<T>(_ block: () throws -> T) throws -> T {
        if isOnCommandQueue {
            return try block()
        }

        var result: Result<T, Error>!
        commandQueue.sync {
            do {
                result = .success(try block())
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }

    // MARK: - CustomDebugStringConvertible

    public var debugDescription: String {
        [
            "## PumpComm",
            "pumpState: \(String(reflecting: pumpState))",
            "delegate: \(String(describing: delegate != nil))",
            ""
        ].joined(separator: "\n")
    }
}

extension PumpComm: PumpCommSessionDelegate {
    public func pumpCommSession(_ pumpCommSession: PumpCommSession, didChange state: PumpState) {
        pumpCommSession.assertOnSessionQueue()
        delegate?.pumpComm(self, didChange: state)
    }

    public func pumpCommSession(
        _ pumpCommSession: PumpCommSession,
        didReceive message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    ) {
        pumpCommSession.assertOnSessionQueue()
        delegate?.pumpComm(
            self,
            didReceive: message,
            metadata: metadata,
            characteristic: characteristic,
            txId: txId
        )
    }

    public func pumpCommSession(_ pumpCommSession: PumpCommSession, didReceiveQualifyingEvents events: Set<QualifyingEvent>) {
        pumpCommSession.assertOnSessionQueue()
        delegate?.pumpComm(self, didReceiveQualifyingEvents: events)
    }
}
