import Dispatch
import Foundation
import TandemCore

protocol PumpCommSessionDelegate: AnyObject {
    func pumpCommSession(_ pumpCommSession: PumpCommSession, didChange state: PumpState)
    func pumpCommSession(
        _ pumpCommSession: PumpCommSession,
        didReceive message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    )
}

public class PumpCommSession {
    private let sessionQueue = DispatchQueue(label: "com.jwoglom.TandemKit.PumpCommSession.queue")
    private(set) var state: PumpState
    weak var delegate: PumpCommSessionDelegate?
    private let logger = PumpLogger(label: "TandemKit.PumpCommSession")
    private static let fallbackPairingCode = "000000"

    #if DEBUG
        static var testOverrideJpakeArtifacts: (() -> (derivedSecret: Data, serverNonce: Data))?
    #endif

    init(pumpState: PumpState, delegate: PumpCommSessionDelegate? = nil) {
        state = pumpState
        self.delegate = delegate
    }

    public func runSession(withName _: String, _ block: @escaping @Sendable() -> Void) {
        sessionQueue.async(execute: block)
    }

    public func runSynchronously<T>(withName _: String, _ block: @escaping @Sendable() throws -> T) rethrows -> T {
        try sessionQueue.sync {
            try block()
        }
    }

    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
    }

    func handleIncoming(
        message: Message,
        metadata: MessageMetadata?,
        characteristic: CharacteristicUUID,
        txId: UInt8
    ) {
        assertOnSessionQueue()
        delegate?.pumpCommSession(
            self,
            didReceive: message,
            metadata: metadata,
            characteristic: characteristic,
            txId: txId
        )
    }

    public func pair(transport: PumpMessageTransport, peripheralUuid: String, pairingCode: String) throws {
        assertOnSessionQueue()
        logger.info("[PumpCommSession] Starting pair, shortCode=\(isShortPairingCode(pairingCode))")
        if isShortPairingCode(pairingCode) {
            try pairUsingJpake(transport: transport, peripheralUuid: peripheralUuid, pairingCode: pairingCode)
        } else {
            try pairUsingPumpChallenge(transport: transport, pairingCode: pairingCode)
        }
    }

    private func isShortPairingCode(_ pairingCode: String) -> Bool {
        pairingCode.count == 6
    }

    private func pairUsingPumpChallenge(transport: PumpMessageTransport, pairingCode: String) throws {
        let appInstanceId = 0

        guard let challengeRequest = CentralChallengeRequestBuilder.create(appInstanceId: appInstanceId) else {
            throw PumpCommError.requestConstructionFailed(reason: "CentralChallengeRequestBuilder returned nil")
        }

        logger.debug("[PumpCommSession] PumpChallenge centralChallengeRequest ready")

        let responseMessage = try transport.sendMessage(challengeRequest)
        logger.debug("[PumpCommSession] Received central challenge response: \(type(of: responseMessage))")
        guard let centralResponse = responseMessage as? CentralChallengeResponse else {
            logger
                .error("[PumpCommSession] Unexpected central challenge response payload: \(String(describing: responseMessage))")
            throw PumpCommError.unexpectedResponse(
                expected: String(describing: CentralChallengeResponse.self),
                actual: String(describing: type(of: responseMessage))
            )
        }

        let challengeMessage = try PumpChallengeRequestBuilder.create(
            challengeResponse: centralResponse,
            pairingCode: pairingCode
        )
        guard let pumpChallengeRequest = challengeMessage as? PumpChallengeRequest else {
            throw PumpCommError.pumpChallengeError
        }

        logger.debug("[PumpCommSession] Sending PumpChallengeRequest")

        let pumpChallengeResponseMessage = try transport.sendMessage(pumpChallengeRequest)
        logger.debug("[PumpCommSession] Received pump challenge response: \(type(of: pumpChallengeResponseMessage))")
        guard let pumpChallengeResponse = pumpChallengeResponseMessage as? PumpChallengeResponse,
              pumpChallengeResponse.success
        else {
            logger.error("[PumpCommSession] Pump challenge response invalid: \(String(describing: pumpChallengeResponseMessage))")
            throw PumpCommError.invalidPumpChallengeResponse
        }

        PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)

        logger.info("[PumpCommSession] Legacy pairing succeeded; cleared artifacts")

        state.derivedSecret = nil
        state.serverNonce = nil
        delegate?.pumpCommSession(self, didChange: state)
        logger.debug("[PumpCommSession] delegate notified of PumpState change (legacy)")
    }

    private func pairUsingJpake(transport: PumpMessageTransport, peripheralUuid: String, pairingCode: String) throws {
        defer {
            JpakeAuthBuilder.clearInstance()
        }

        guard let provider = JpakeAuthBuilder.providerFactory.make(
            pairingCode: pairingCode,
            derivedSecret: nil,
            random: JpakeAuthBuilder.defaultRandom
        ) else {
            logger.error("[PumpCommSession] Pairing cannot be performed, no JPAKE provider available")
            throw PumpCommError.jpakeUnavailable
        }

        let builder = JpakeAuthBuilder.initializeWithPairingCode(pairingCode, provider: provider)
        logger.debug("[PumpCommSession] initial state: done=\(builder.done()) invalid=\(builder.invalid())")
        while !builder.done(), !builder.invalid() {
            let maybeRequest = builder.nextRequest()
            logger.debug("[PumpCommSession] nextRequest -> \(String(describing: maybeRequest))")
            guard let request = maybeRequest else { break }
            logger.debug("[PumpCommSession] Sending JPAKE request: \(request)")
            let response = try transport.sendMessage(request)
            logger.debug("[PumpCommSession] Received JPAKE response: \(response)")
            builder.processResponse(response)
            logger.debug("[PumpCommSession] initial state: done=\(builder.done()) invalid=\(builder.invalid())")
            logger.debug("[PumpCommSession] builder state: done=\(builder.done()) invalid=\(builder.invalid())")
        }
        guard builder.done(), let secret = builder.getDerivedSecret(), let serverNonce = builder.getServerNonce() else {
            logger
                .error(
                    "[PumpCommSession] JPAKE failed: done=\(builder.done()) invalid=\(builder.invalid()) derivedSecret=\(builder.getDerivedSecret() != nil) serverNonce=\(builder.getServerNonce() != nil)"
                )
            throw PumpCommError.missingAuthenticationKey
        }

        logger.info("[PumpCommSession] JPAKE pairing succeeded; waiting 250ms before session initialization")
        Thread.sleep(forTimeInterval: 0.25)

        // Temporarily store artifacts so we can send TimeSinceResetRequest
        PumpStateSupplier.storePairingArtifacts(derivedSecret: secret, serverNonce: serverNonce)

        // Fetch timeSinceReset to initialize the session properly
        logger.info("[PumpCommSession] Fetching timeSinceReset to initialize authenticated session")
        let timeSinceResetResponse = try transport.sendMessage(TimeSinceResetRequest())
        guard let response = timeSinceResetResponse as? TimeSinceResetResponse else {
            logger.error("[PumpCommSession] Failed to get timeSinceReset response")
            throw PumpCommError.timeSyncFailed
        }

        // Fetch API version and pump version for session initialization
        logger.info("[PumpCommSession] Fetching API version")
        _ = try transport.sendMessage(ApiVersionRequest())

        logger.info("[PumpCommSession] Fetching pump version")
        _ = try transport.sendMessage(PumpVersionRequest())

        logger.info("[PumpCommSession] Session fully authenticated with timeSinceReset: \(response.pumpTimeSinceReset)")

        state.derivedSecret = secret
        state.serverNonce = serverNonce
        state.peripheralUuid = peripheralUuid
        state.timeSinceReset = response.pumpTimeSinceReset
        delegate?.pumpCommSession(self, didChange: state)
        logger.debug("[PumpCommSession] delegate notified of PumpState change (JPAKE)")
    }

    func confirmAuthentication(
        transport: PumpMessageTransport,
        peripheralUuid: String,
        derivedSecret: Data
    ) throws {
        assertOnSessionQueue()

        guard !derivedSecret.isEmpty else {
            logger.error("[PumpCommSession] Stored derived secret missing; cannot confirm authentication")
            throw PumpCommError.missingAuthenticationKey
        }

        defer {
            JpakeAuthBuilder.clearInstance()
        }

        let storedPairingCode = PumpStateSupplier.storedPairingCode()
        let pairingCode = storedPairingCode ?? Self.fallbackPairingCode

        guard let provider = JpakeAuthBuilder.providerFactory.make(
            pairingCode: pairingCode,
            derivedSecret: derivedSecret,
            random: JpakeAuthBuilder.defaultRandom
        ) else {
            logger.error("[PumpCommSession] Authentication cannot be performed, no JPAKE provider available")
            throw PumpCommError.jpakeUnavailable
        }

        logger.info(
            "[PumpCommSession] Starting stored-credential authentication, pairingCodeStored=\(storedPairingCode != nil)"
        )
        let builder = JpakeAuthBuilder.initializeWithDerivedSecret(
            pairingCode: pairingCode,
            derivedSecret: derivedSecret,
            provider: provider
        )
        logger.debug("[PumpCommSession] authentication state: done=\(builder.done()) invalid=\(builder.invalid())")

        while !builder.done(), !builder.invalid() {
            guard let request = builder.nextRequest() else { break }
            logger.debug("[PumpCommSession] Sending JPAKE confirm request: \(request)")
            let response = try transport.sendMessage(request)
            logger.debug("[PumpCommSession] Received JPAKE confirm response: \(response)")
            builder.processResponse(response)
            logger.debug("[PumpCommSession] authentication state: done=\(builder.done()) invalid=\(builder.invalid())")
        }

        guard builder.done(), let serverNonce = builder.getServerNonce() else {
            logger
                .error(
                    "[PumpCommSession] Stored-credential authentication failed: done=\(builder.done()) invalid=\(builder.invalid())"
                )
            throw PumpCommError.missingAuthenticationKey
        }

        logger.info("[PumpCommSession] Stored-credential authentication succeeded; refreshing pump state")
        state.derivedSecret = derivedSecret
        state.serverNonce = serverNonce
        state.peripheralUuid = peripheralUuid
        delegate?.pumpCommSession(self, didChange: state)
        logger.debug("[PumpCommSession] delegate notified of PumpState change (JPAKE confirm)")
    }

}
