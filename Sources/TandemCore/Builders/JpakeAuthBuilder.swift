import Foundation

public class JpakeAuthBuilder {
    private let log = TandemLogger(category: "JpakeAuthBuilder")
    private static var instance: JpakeAuthBuilder?

    let cryptoProvider: SwiftECCJpakeProvider
    public private(set) var sentMessages: [Message]
    public private(set) var receivedMessages: [Message]
    var step: JpakeStep
    private var clientRound1: Data?
    /// The two frames `clientRound1` is sent as, split on the real group boundary rather than at a
    /// fixed offset — see `JpakeRound1Framing`.
    private var clientRound1Frames: (first: Data, second: Data)?
    private var serverRound1: Data?
    private var clientRound2: Data?
    private var serverRound2: Data?
    private var derivedSecret: Data?
    private var serverNonce3: Data?
    private var clientNonce4: Data?
    private var serverHashDigest4: Data?
    private var serverNonce4: Data?

    init(provider: SwiftECCJpakeProvider, derivedSecret: Data?) {
        cryptoProvider = provider
        self.derivedSecret = derivedSecret
        step = Self.decideInitialStep(derivedSecret: derivedSecret)
        sentMessages = []
        receivedMessages = []
    }

    static func initializeWithPairingCode(_ pairingCode: String) -> JpakeAuthBuilder {
        let provider = SwiftECCJpakeProvider(
            pairingCode: pairingCode,
            derivedSecret: nil,
            rand: defaultRandom
        )
        return JpakeAuthBuilder(provider: provider, derivedSecret: nil)
    }

    static func initializeWithDerivedSecret(pairingCode: String, derivedSecret: Data) -> JpakeAuthBuilder {
        let provider = SwiftECCJpakeProvider(
            pairingCode: pairingCode,
            derivedSecret: derivedSecret,
            rand: defaultRandom
        )
        return initializeWithDerivedSecret(pairingCode: pairingCode, derivedSecret: derivedSecret, provider: provider)
    }

    static func initializeWithDerivedSecret(
        pairingCode _: String,
        derivedSecret: Data,
        provider: SwiftECCJpakeProvider
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

    public func resetStep() {
        step = Self.decideInitialStep(derivedSecret: derivedSecret)
    }

    public func nextRequest() -> (any PumpRequest)? {
        var request: (any PumpRequest)?
        switch step {
        case .BOOTSTRAP_INITIAL:
            let round1 = cryptoProvider.makeRound1()
            clientRound1 = round1
            // Split on the group boundary, not at byte 165: a ZKP scalar drops its leading zero
            // bytes, so round 1 is 330 bytes only ~99.2% of the time.
            if let frames = JpakeRound1Framing.splitRound1(round1) {
                clientRound1Frames = frames
                request = Jpake1aRequest(appInstanceId: 0, centralChallenge: frames.first)
                step = .ROUND_1A_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 1 payload malformed (\(round1.count) bytes)")
                step = .INVALID
            }
        case .ROUND_1A_RECEIVED:
            if let frames = clientRound1Frames {
                request = Jpake1bRequest(appInstanceId: 0, centralChallenge: frames.second)
                step = .ROUND_1B_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 1 client material missing for 1b request")
                step = .INVALID
            }
        case .ROUND_1B_RECEIVED:
            let round2 = cryptoProvider.makeRound2()
            clientRound2 = round2
            // Round 2 is a single group, so it fits one frame; it is short for the same
            // leading-zero reason round 1 is, and gets the same zero padding.
            if JpakeRound1Framing.groupLength(in: round2, at: 0) != nil {
                request = Jpake2Request(appInstanceId: 0, centralChallenge: JpakeRound1Framing.padToFrame(round2))
                step = .ROUND_2_SENT
            } else {
                log.error("[JpakeAuthBuilder] Round 2 payload malformed (\(round2.count) bytes)")
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
            log.debug("[JpakeAuthBuilder] nextRequest returning nil for step=\(step)")
            request = nil
        }
        if let request {
            sentMessages.append(request)
        }
        log.debug("[JpakeAuthBuilder] nextRequest end step=\(step)")
        return request
    }

    public func processResponse(_ response: Message) {
        receivedMessages.append(response)
        if let m = response as? Jpake1aResponse {
            serverRound1 = m.centralChallengeHash
            step = .ROUND_1A_RECEIVED
        } else if let m = response as? Jpake1bResponse {
            if let sr1 = serverRound1 {
                // The pump's halves are fixed-size frames too, so its first half carries trailing
                // padding whenever its own scalar came up short. Concatenating them raw would put
                // that padding in the middle of the stream and misalign the second group.
                let full = JpakeRound1Framing.joinRound1(first: sr1, second: m.centralChallengeHash)
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
        log.debug("[JpakeAuthBuilder] processResponse step(after)=\(step)")
    }

    public func done() -> Bool {
        step == .COMPLETE
    }

    public func invalid() -> Bool {
        step == .INVALID
    }

    /// The pump answered key confirmation with a digest that is not the one this side derived,
    /// which is what a different pairing code on each side produces.
    public func rejectedAtKeyConfirmation() -> Bool {
        step == .INVALID && receivedMessages.last is Jpake4KeyConfirmationResponse
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
    static let shared = NonBlockingRandom()

    private let lock = NSLock()

    private init() {}

    func next(count: Int) -> Data {
        guard count > 0 else { return Data() }

        lock.lock()
        defer { lock.unlock() }

        var data = Data(count: count)

        // Fallback to SystemRandomNumberGenerator
        var generator = SystemRandomNumberGenerator()
        for index in 0 ..< count {
            data[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &generator)
        }
        return data
    }
}
