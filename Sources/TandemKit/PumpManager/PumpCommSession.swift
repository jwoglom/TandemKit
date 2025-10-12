import Foundation
import TandemCore

protocol PumpCommSessionDelegate: AnyObject {
    func pumpCommSession(_ pumpCommSession: PumpCommSession, didChange state: PumpState)
}

public class PumpCommSession {
    private let sessionQueue = DispatchQueue(label: "com.jwoglom.TandemKit.PumpCommSession.queue")
    private(set) var state: PumpState
    weak var delegate: PumpCommSessionDelegate?

    init(pumpState: PumpState, delegate: PumpCommSessionDelegate? = nil) {
        self.state = pumpState
        self.delegate = delegate
    }

    public func runSession(withName name: String, _ block: @escaping @Sendable () -> Void) {
        sessionQueue.async(execute: block)
    }

    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
    }

    public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
        assertOnSessionQueue()
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

        var centralChallenge: CentralChallengeRequest?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.async {
            centralChallenge = CentralChallengeRequestBuilder.create(appInstanceId: appInstanceId)
            group.leave()
        }
        group.wait()

        guard let challengeRequest = centralChallenge else {
            throw PumpCommError.other
        }

        let responseMessage = try transport.sendMessage(challengeRequest)
        guard let centralResponse = responseMessage as? CentralChallengeResponse else {
            throw PumpCommError.other
        }

        let challengeMessage = try PumpChallengeRequestBuilder.create(challengeResponse: centralResponse, pairingCode: pairingCode)
        guard let pumpChallengeRequest = challengeMessage as? PumpChallengeRequest else {
            throw PumpCommError.other
        }

        let pumpChallengeResponseMessage = try transport.sendMessage(pumpChallengeRequest)
        guard let pumpChallengeResponse = pumpChallengeResponseMessage as? PumpChallengeResponse, pumpChallengeResponse.success else {
            throw PumpCommError.other
        }

        let artifactsGroup = DispatchGroup()
        artifactsGroup.enter()
        DispatchQueue.main.async {
            PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)
            artifactsGroup.leave()
        }
        artifactsGroup.wait()

        state.derivedSecret = nil
        state.serverNonce = nil
        delegate?.pumpCommSession(self, didChange: state)
    }

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    private func pairUsingJpake(transport: PumpMessageTransport, pairingCode: String) throws {
        defer {
            JpakeAuthBuilder.clearInstance()
        }

        let builder = JpakeAuthBuilder.initializeWithPairingCode(pairingCode)
        while !builder.done() && !builder.invalid() {
            guard let request = builder.nextRequest() else { break }
            let response = try transport.sendMessage(request)
            builder.processResponse(response)
        }
        guard builder.done(), let secret = builder.getDerivedSecret(), let serverNonce = builder.getServerNonce() else {
            throw PumpCommError.missingAuthenticationKey
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.async {
            PumpStateSupplier.storePairingArtifacts(derivedSecret: secret, serverNonce: serverNonce)
            group.leave()
        }
        group.wait()

        state.derivedSecret = secret
        state.serverNonce = serverNonce
        delegate?.pumpCommSession(self, didChange: state)
    }
#endif
}
