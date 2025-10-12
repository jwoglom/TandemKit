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

    #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
        assertOnSessionQueue()
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
