import Foundation
import LoopKit
import TandemCore
#if canImport(os)
    import os
#endif

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
}

public class PumpComm: CustomDebugStringConvertible {
    var manager: Any? // TODO: Replace with actual PeripheralManager type when available

    public weak var delegate: PumpCommDelegate?

    public let log = OSLog(category: "PumpComm")

    public var retryPolicy: PumpCommRetryPolicy
    private let delayHandler: (TimeInterval) -> Void

    private var session: PumpCommSession?

    // Only valid to access on the session serial queue
    private var pumpState: PumpState? {
        didSet {
            if let newValue = pumpState, newValue != oldValue {
                delegate?.pumpComm(self, didChange: newValue)
            }
        }
    }

    public var isDevicePaired: Bool {
        pumpState?.derivedSecret != nil
    }

    public var isAuthenticated: Bool {
        pumpState?.derivedSecret != nil
    }

    // TODO(jwoglom): device name or PIN?
    public init(
        pumpState: PumpState?,
        retryPolicy: PumpCommRetryPolicy = ExponentialPumpCommRetryPolicy(),
        delayHandler: ((TimeInterval) -> Void)? = nil
    ) {
        delegate = nil
        self.retryPolicy = retryPolicy
        self.delayHandler = delayHandler ?? PumpComm.defaultDelayHandler

        let initialState = pumpState ?? PumpState()
        self.pumpState = pumpState ?? initialState
        session = PumpCommSession(pumpState: initialState, delegate: self)
    }

    private static func defaultDelayHandler(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        Thread.sleep(forTimeInterval: interval)
    }

    #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
        public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
            let session = ensureSession()
            log.debug("PumpComm pair started")
            try session.runSynchronously(withName: "Pairing") {
                try session.pair(transport: transport, pairingCode: pairingCode)
            }
            log.debug("PumpComm pair finished")
        }
    #endif

    private func ensureSession() -> PumpCommSession {
        if let session = self.session {
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
        log.debug("sendMessage: attempting to send %@", String(describing: message))

        var attempt = 0

        while true {
            attempt += 1
            do {
                let response = try transport.sendMessage(message)
                log.debug("sendMessage: received response %@", String(describing: response))

                if let errorResponse = response as? ErrorResponse {
                    log.error(
                        "sendMessage: pump returned error response (code=%{public}d) on attempt %{public}d",
                        errorResponse.errorCodeId,
                        attempt
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
                log.error("sendMessage pump communication error: %{public}@", String(describing: error))
                throw error
            } catch {
                log.error("sendMessage unexpected error: %{public}@", String(describing: error))
                throw PumpCommError.other
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
            log.debug("sendMessage: scheduling retry for fault code %{public}d after %{public}.2f s", response.errorCodeId, delay)
            delayHandler(delay)
            return .retry
        case .doNotRetry:
            log.error("sendMessage: not retrying fault code %{public}d", response.errorCodeId)
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
                "sendMessage unexpected response type: expected %@, got %@",
                String(describing: expectedType),
                String(describing: type(of: response))
            )
            throw PumpCommError.errorResponse(response: response)
        }

        return typedResponse
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
        pumpState = state
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
}
