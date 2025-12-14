import Foundation

public class JpakeAuthBuilder {
    private let log = PumpLogger(label: "JpakeAuthBuilder")
    private static var instance: JpakeAuthBuilder?

    public static var providerFactory: JpakeProviderFactory = DefaultJpakeProviderFactory()

    let cryptoProvider: JpakeProvider
    public private(set) var sentMessages: [Message]
    public private(set) var receivedMessages: [Message]
    var step: JpakeStep
    private var clientRound1: Data?
    private var serverRound1: Data?
    private var clientRound2: Data?
    private var serverRound2: Data?
    private var derivedSecret: Data?
    private var serverNonce3: Data?
    private var clientNonce4: Data?
    private var serverHashDigest4: Data?
    private var serverNonce4: Data?

    init(provider: JpakeProvider, derivedSecret: Data?) {
        cryptoProvider = provider
        self.derivedSecret = derivedSecret
        step = Self.decideInitialStep(derivedSecret: derivedSecret)
        sentMessages = []
        receivedMessages = []
    }

    public static func initializeWithPairingCode(_ pairingCode: String) -> JpakeAuthBuilder {
        guard let provider = providerFactory.make(
            pairingCode: pairingCode,
            derivedSecret: nil,
            random: defaultRandom
        ) else {
            fatalError("JPAKE provider unavailable")
        }
        return initializeWithPairingCode(pairingCode, provider: provider)
    }

    public static func initializeWithPairingCode(_ pairingCode: String, provider: JpakeProvider) -> JpakeAuthBuilder {
        if let inst = instance, inst.cryptoProvider.pairingCode == pairingCode {
            return inst
        }
        instance = JpakeAuthBuilder(provider: provider, derivedSecret: nil)
        return instance!
    }

    public static func initializeWithDerivedSecret(pairingCode: String, derivedSecret: Data) -> JpakeAuthBuilder {
        guard let provider = providerFactory.make(
            pairingCode: pairingCode,
            derivedSecret: derivedSecret,
            random: defaultRandom
        ) else {
            fatalError("JPAKE provider unavailable")
        }
        return initializeWithDerivedSecret(pairingCode: pairingCode, derivedSecret: derivedSecret, provider: provider)
    }

    public static func initializeWithDerivedSecret(
        pairingCode: String,
        derivedSecret: Data,
        provider: JpakeProvider
    ) -> JpakeAuthBuilder {
        instance = JpakeAuthBuilder(provider: provider, derivedSecret: derivedSecret)
        return instance!
    }

    public static func getInstance() -> JpakeAuthBuilder {
        guard let inst = instance else {
            fatalError("JPAKE auth session does not exist")
        }
        return inst
    }

    public static func clearInstance() {
        instance = nil
    }

    public func nextRequest() -> Message? {
        log.trace("[JpakeAuthBuilder] nextRequest start")
        var request: Message?
        switch step {
        case .BOOTSTRAP_INITIAL:
            clientRound1 = cryptoProvider.makeRound1()
            if let round1 = clientRound1, round1.count >= 165 {
                let challenge = round1.subdata(in: 0 ..< 165)
                request = Jpake1aRequest(appInstanceId: 0, centralChallenge: challenge)
                step = .ROUND_1A_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 1 payload missing")
                step = .INVALID
            }
        case .ROUND_1A_RECEIVED:
            if let round1 = clientRound1, round1.count >= 330 {
                let challenge = round1.subdata(in: 165 ..< 330)
                request = Jpake1bRequest(appInstanceId: 0, centralChallenge: challenge)
                step = .ROUND_1B_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 1 client material missing for 1b request")
                step = .INVALID
            }
        case .ROUND_1B_RECEIVED:
            clientRound2 = cryptoProvider.makeRound2()
            if let round2 = clientRound2, round2.count >= 165 {
                let challenge = round2.subdata(in: 0 ..< 165)
                request = Jpake2Request(appInstanceId: 0, centralChallenge: challenge)
                step = .ROUND_2_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 2 payload missing")
                step = .INVALID
            }
        case .ROUND_2_RECEIVED:
            request = Jpake3SessionKeyRequest(challengeParam: 0)
            derivedSecret = cryptoProvider.deriveSecret()
            step = .CONFIRM_3_SENT
        case .CONFIRM_INITIAL:
            guard derivedSecret != nil else {
                log.error("[JpakeAuthBuilder] Derived secret unavailable for confirmation")
                step = .INVALID
                break
            }
            request = Jpake3SessionKeyRequest(challengeParam: 0)
            step = .CONFIRM_3_SENT
        case .CONFIRM_3_RECEIVED:
            guard let serverNonce3, let derivedSecret else {
                log.error("[JpakeAuthBuilder] Missing state for confirm round 4 request")
                step = .INVALID
                break
            }
            clientNonce4 = generateNonce()
            let hashDigest3 = HmacSha256.hmac(
                clientNonce4!,
                key: Hkdf.build(nonce: serverNonce3, keyMaterial: derivedSecret)
            )
            request = Jpake4KeyConfirmationRequest(
                appInstanceId: 0,
                nonce: clientNonce4!,
                reserved: Jpake4KeyConfirmationRequest.RESERVED,
                hashDigest: hashDigest3
            )
            step = .CONFIRM_4_SENT
        case .CONFIRM_4_RECEIVED:
            guard let serverNonce4, let serverNonce3, let derivedSecret, let serverHashDigest4 else {
                log.error("[JpakeAuthBuilder] Missing state for confirm round 4 validation")
                step = .INVALID
                break
            }
            let hashDigest4 = HmacSha256.hmac(
                serverNonce4,
                key: Hkdf.build(nonce: serverNonce3, keyMaterial: derivedSecret)
            )
            step = serverHashDigest4 == hashDigest4 ? .COMPLETE : .INVALID
            request = nil
        default:
            log.trace("[JpakeAuthBuilder] nextRequest returning nil for step=\(step)")
            request = nil
        }
        if let request {
            sentMessages.append(request)
        }
        log.trace("[JpakeAuthBuilder] nextRequest end step=\(step)")
        return request
    }

    public func processResponse(_ response: Message) {
        receivedMessages.append(response)
        log.trace("[JpakeAuthBuilder] processResponse \(type(of: response)) step(before)=\(step)")
        if let m = response as? Jpake1aResponse {
            serverRound1 = m.centralChallengeHash
            step = .ROUND_1A_RECEIVED
        } else if let m = response as? Jpake1bResponse {
            if let sr1 = serverRound1 {
                let full = Bytes.combine(sr1, m.centralChallengeHash)
                serverRound1 = full
                cryptoProvider.readRound1(full)
            }
            step = .ROUND_1B_RECEIVED
        } else if let m = response as? Jpake2Response {
            serverRound2 = m.centralChallengeHash
            cryptoProvider.readRound2(serverRound2!)
            step = .ROUND_2_RECEIVED
        } else if let m = response as? Jpake3SessionKeyResponse {
            serverNonce3 = m.deviceKeyNonce
            step = .CONFIRM_3_RECEIVED
        } else if let m = response as? Jpake4KeyConfirmationResponse {
            serverNonce4 = m.nonce
            serverHashDigest4 = m.hashDigest
            step = .CONFIRM_4_RECEIVED
        }
        log.trace("[JpakeAuthBuilder] processResponse step(after)=\(step)")
    }

    public func done() -> Bool {
        step == .COMPLETE
    }

    public func invalid() -> Bool {
        step == .INVALID
    }

    public func getDerivedSecret() -> Data? {
        derivedSecret
    }

    public func getServerNonce() -> Data? {
        serverNonce3
    }

    static func decideInitialStep(derivedSecret: Data?) -> JpakeStep {
        if let ds = derivedSecret, !ds.isEmpty {
            return .CONFIRM_INITIAL
        } else {
            return .BOOTSTRAP_INITIAL
        }
    }

    static func pairingCodeToBytes(_ pairingCode: String) -> Data {
        var ret = Data(count: pairingCode.count)
        for (idx, char) in pairingCode.enumerated() {
            ret[idx] = charCode(char)
        }
        return ret
    }

    static func charCode(_ c: Character) -> UInt8 {
        switch c {
        case "0": return 48
        case "1": return 49
        case "2": return 50
        case "3": return 51
        case "4": return 52
        case "5": return 53
        case "6": return 54
        case "7": return 55
        case "8": return 56
        case "9": return 57
        default: return 0xFF
        }
    }

    public static func defaultRandom(_ count: Int) -> Data {
        NonBlockingRandom.shared.next(count: count)
    }

    private func generateNonce() -> Data {
        JpakeAuthBuilder.defaultRandom(8)
    }
}

private final class NonBlockingRandom {
    private let log = PumpLogger(label: "NonBlockingRandom")
    static let shared = NonBlockingRandom()

    private let lock = NSLock()

    private init() {}

    func next(count: Int) -> Data {
        guard count > 0 else { return Data() }

        lock.lock()
        defer { lock.unlock() }

        var data = Data(count: count)

        #if canImport(Darwin)
            // Use Apple's secure random API which is guaranteed non-blocking
            let result = data.withUnsafeMutableBytes { bufferPtr in
                SecRandomCopyBytes(kSecRandomDefault, count, bufferPtr.baseAddress!)
            }

            if result == errSecSuccess {
                return data
            }

            log.warning(
                "[NonBlockingRandom] Warning: SecRandomCopyBytes failed with \(result), falling back to SystemRandomNumberGenerator"
            )
        #endif

        // Fallback to SystemRandomNumberGenerator
        var generator = SystemRandomNumberGenerator()
        for index in 0 ..< count {
            data[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &generator)
        }
        return data
    }
}
