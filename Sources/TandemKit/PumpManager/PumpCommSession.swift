import Foundation
import Dispatch
import TandemCore

protocol PumpCommSessionDelegate: AnyObject {
    func pumpCommSession(_ pumpCommSession: PumpCommSession, didChange state: PumpState)
}

public class PumpCommSession {
    private let sessionQueue = DispatchQueue(label: "com.jwoglom.TandemKit.PumpCommSession.queue")
    private(set) var state: PumpState
    weak var delegate: PumpCommSessionDelegate?

#if DEBUG
    static var testOverrideJpakeArtifacts: (() -> (derivedSecret: Data, serverNonce: Data))?
#endif

    init(pumpState: PumpState, delegate: PumpCommSessionDelegate? = nil) {
        self.state = pumpState
        self.delegate = delegate
    }

    public func runSession(withName name: String, _ block: @escaping @Sendable () -> Void) {
        sessionQueue.async(execute: block)
    }

    public func runSynchronously<T>(withName name: String, _ block: @escaping @Sendable () throws -> T) rethrows -> T {
        try sessionQueue.sync {
            try block()
        }
    }

    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
    }

    public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
        assertOnSessionQueue()
        print("[PumpCommSession] Starting pair, shortCode=\(isShortPairingCode(pairingCode))")
        if isShortPairingCode(pairingCode) {
#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            try pairUsingJpake(transport: transport, pairingCode: pairingCode)
#else
            throw PumpCommError.other
#endif
        } else {
            try pairUsingPumpChallenge(transport: transport, pairingCode: pairingCode)
        }
    }

    private func isShortPairingCode(_ pairingCode: String) -> Bool {
        return pairingCode.count == 6
    }

    private func pairUsingPumpChallenge(transport: PumpMessageTransport, pairingCode: String) throws {
        let appInstanceId = 0

        guard let challengeRequest = CentralChallengeRequestBuilder.create(appInstanceId: appInstanceId) else {
            throw PumpCommError.other
        }

        print("[PumpCommSession] PumpChallenge centralChallengeRequest ready")

        let responseMessage = try transport.sendMessage(challengeRequest)
        print("[PumpCommSession] Received central challenge response: \(type(of: responseMessage))")
        guard let centralResponse = responseMessage as? CentralChallengeResponse else {
            print("[PumpCommSession] Unexpected central challenge response payload: \(String(describing: responseMessage))")
            throw PumpCommError.other
        }

        let challengeMessage = try PumpChallengeRequestBuilder.create(challengeResponse: centralResponse, pairingCode: pairingCode)
        guard let pumpChallengeRequest = challengeMessage as? PumpChallengeRequest else {
            throw PumpCommError.other
        }

        print("[PumpCommSession] Sending PumpChallengeRequest")

        let pumpChallengeResponseMessage = try transport.sendMessage(pumpChallengeRequest)
        print("[PumpCommSession] Received pump challenge response: \(type(of: pumpChallengeResponseMessage))")
        guard let pumpChallengeResponse = pumpChallengeResponseMessage as? PumpChallengeResponse, pumpChallengeResponse.success else {
            print("[PumpCommSession] Pump challenge response invalid: \(String(describing: pumpChallengeResponseMessage))")
            throw PumpCommError.other
        }

        PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)

        print("[PumpCommSession] Legacy pairing succeeded; cleared artifacts")

        state.derivedSecret = nil
        state.serverNonce = nil
        delegate?.pumpCommSession(self, didChange: state)
        print("[PumpCommSession] delegate notified of PumpState change (legacy)")
    }

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    private func pairUsingJpake(transport: PumpMessageTransport, pairingCode: String) throws {
#if DEBUG
        if let override = PumpCommSession.testOverrideJpakeArtifacts {
            let artifacts = override()
            PumpStateSupplier.storePairingArtifacts(derivedSecret: artifacts.derivedSecret, serverNonce: artifacts.serverNonce)
            state.derivedSecret = artifacts.derivedSecret
            state.serverNonce = artifacts.serverNonce
            delegate?.pumpCommSession(self, didChange: state)
            print("[PumpCommSession] JPAKE pairing bypassed via test override")
            return
        }
#endif
        defer {
            JpakeAuthBuilder.clearInstance()
        }

        let builder = JpakeAuthBuilder.initializeWithPairingCode(pairingCode)
        print("[PumpCommSession] initial state: done=\(builder.done()) invalid=\(builder.invalid())")
        while !builder.done() && !builder.invalid() {
            let maybeRequest = builder.nextRequest()
            print("[PumpCommSession] nextRequest -> \(String(describing: maybeRequest))")
            guard let request = maybeRequest else { break }
            print("[PumpCommSession] Sending JPAKE request: \(type(of: request))")
            let response = try transport.sendMessage(request)
            print("[PumpCommSession] Received JPAKE response: \(type(of: response))")
            builder.processResponse(response)
            print("[PumpCommSession] builder state: done=\(builder.done()) invalid=\(builder.invalid())")
        }
        guard builder.done(), let secret = builder.getDerivedSecret(), let serverNonce = builder.getServerNonce() else {
            print("[PumpCommSession] JPAKE failed: done=\(builder.done()) invalid=\(builder.invalid()) derivedSecret=\(builder.getDerivedSecret() != nil) serverNonce=\(builder.getServerNonce() != nil)")
            throw PumpCommError.missingAuthenticationKey
        }

        PumpStateSupplier.storePairingArtifacts(derivedSecret: secret, serverNonce: serverNonce)

        print("[PumpCommSession] JPAKE pairing succeeded; stored artifacts")

        state.derivedSecret = secret
        state.serverNonce = serverNonce
        delegate?.pumpCommSession(self, didChange: state)
        print("[PumpCommSession] delegate notified of PumpState change (JPAKE)")
    }
#endif
}
