import Foundation

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)

public class JpakeAuthBuilder {
    private static var instance: JpakeAuthBuilder? = nil

    let pairingCode: String
    var sentMessages: [Message]
    var receivedMessages: [Message]
    var clientRound1: Data?
    var serverRound1: Data?
    var clientRound2: Data?
    var serverRound2: Data?
    var derivedSecret: Data?
    var serverNonce3: Data?
    var clientNonce4: Data?
    var serverHashDigest4: Data?
    var serverNonce4: Data?

    var cli: EcJpake
    var rand: EcJpake.RandomBytesGenerator
    var step: JpakeStep

    init(pairingCode: String,
         step: JpakeStep,
         clientRound1: Data?,
         serverRound1: Data?,
         clientRound2: Data?,
         serverRound2: Data?,
         derivedSecret: Data?,
         rand: @escaping EcJpake.RandomBytesGenerator) {
        self.pairingCode = pairingCode
        self.cli = EcJpake(role: .client, password: JpakeAuthBuilder.pairingCodeToBytes(pairingCode), random: rand)
        self.sentMessages = []
        self.receivedMessages = []
        self.step = step
        self.clientRound1 = clientRound1
        self.serverRound1 = serverRound1
        self.clientRound2 = clientRound2
        self.serverRound2 = serverRound2
        self.derivedSecret = derivedSecret
        self.rand = rand
    }

    convenience init(pairingCode: String) {
        self.init(pairingCode: pairingCode, step: JpakeAuthBuilder.decideInitialStep(derivedSecret: nil), clientRound1: nil, serverRound1: nil, clientRound2: nil, serverRound2: nil, derivedSecret: nil, rand: JpakeAuthBuilder.defaultRandom)
    }

    convenience init(pairingCode: String, derivedSecret: Data) {
        self.init(pairingCode: pairingCode, step: JpakeAuthBuilder.decideInitialStep(derivedSecret: derivedSecret), clientRound1: nil, serverRound1: nil, clientRound2: nil, serverRound2: nil, derivedSecret: derivedSecret, rand: JpakeAuthBuilder.defaultRandom)
    }

    convenience init(pairingCode: String, derivedSecret: Data?, rand: @escaping EcJpake.RandomBytesGenerator) {
        self.init(pairingCode: pairingCode, step: JpakeAuthBuilder.decideInitialStep(derivedSecret: derivedSecret), clientRound1: nil, serverRound1: nil, clientRound2: nil, serverRound2: nil, derivedSecret: derivedSecret, rand: rand)
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

    public static func initializeWithPairingCode(_ pairingCode: String) -> JpakeAuthBuilder {
        if let inst = instance, inst.pairingCode == pairingCode {
            return inst
        }
        instance = JpakeAuthBuilder(pairingCode: pairingCode)
        return instance!
    }

    public static func initializeWithDerivedSecret(pairingCode: String, derivedSecret: Data) -> JpakeAuthBuilder {
        instance = JpakeAuthBuilder(pairingCode: pairingCode, derivedSecret: derivedSecret)
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
        print("[JpakeAuthBuilder] nextRequest start step=\(step)")
        var request: Message
        switch step {
        case .BOOTSTRAP_INITIAL:
            print("[JpakeAuthBuilder] calling cli.getRound1()")
            clientRound1 = cli.getRound1()
            print("[JpakeAuthBuilder] getRound1 returned bytes=\(clientRound1?.count ?? -1)")
            let challenge = clientRound1!.subdata(in: 0..<165)
            request = Jpake1aRequest(appInstanceId: 0, centralChallenge: challenge)
            step = .ROUND_1A_SENT
            print("[JpakeAuthBuilder] produced Jpake1aRequest")
        case .ROUND_1A_RECEIVED:
            let challenge = clientRound1!.subdata(in: 165..<330)
            request = Jpake1bRequest(appInstanceId: 0, centralChallenge: challenge)
            step = .ROUND_1B_SENT
            print("[JpakeAuthBuilder] produced Jpake1bRequest")
        case .ROUND_1B_RECEIVED:
            clientRound2 = cli.getRound2()
            let challenge = clientRound2!.subdata(in: 0..<165)
            request = Jpake2Request(appInstanceId: 0, centralChallenge: challenge)
            step = .ROUND_2_SENT
            print("[JpakeAuthBuilder] produced Jpake2Request")
        case .ROUND_2_RECEIVED:
            request = Jpake3SessionKeyRequest(challengeParam: 0)
            derivedSecret = cli.deriveSecret()
            step = .CONFIRM_3_SENT
            print("[JpakeAuthBuilder] produced Jpake3SessionKeyRequest")
        case .CONFIRM_INITIAL:
            request = Jpake3SessionKeyRequest(challengeParam: 0)
            step = .CONFIRM_3_SENT
            print("[JpakeAuthBuilder] produced Jpake3SessionKeyRequest (confirm)")
        case .CONFIRM_3_RECEIVED:
            clientNonce4 = generateNonce()
            let hashDigest3 = HmacSha256.hmac(clientNonce4!, key: Hkdf.build(nonce: serverNonce3!, keyMaterial: derivedSecret!))
            request = Jpake4KeyConfirmationRequest(appInstanceId: 0, nonce: clientNonce4!, reserved: Jpake4KeyConfirmationRequest.RESERVED, hashDigest: hashDigest3)
            step = .CONFIRM_4_SENT
            print("[JpakeAuthBuilder] produced Jpake4KeyConfirmationRequest")
        case .CONFIRM_4_RECEIVED:
            let hashDigest4 = HmacSha256.hmac(serverNonce4!, key: Hkdf.build(nonce: serverNonce3!, keyMaterial: derivedSecret!))
            if serverHashDigest4 == hashDigest4 {
                step = .COMPLETE
                print("[JpakeAuthBuilder] pairing complete")
            } else {
                step = .INVALID
                print("[JpakeAuthBuilder] pairing invalid")
            }
            return nil
        default:
            print("[JpakeAuthBuilder] nextRequest returning nil for step=\(step)")
            return nil
        }
        sentMessages.append(request)
        print("[JpakeAuthBuilder] next step now \(step)")
        return request
    }

    public func processResponse(_ response: Message) {
        receivedMessages.append(response)
        print("[JpakeAuthBuilder] processResponse \(type(of: response)) step(before)=\(step)")
        if let m = response as? Jpake1aResponse {
            serverRound1 = m.centralChallengeHash
            step = .ROUND_1A_RECEIVED
            print("[JpakeAuthBuilder] step -> ROUND_1A_RECEIVED")
        } else if let m = response as? Jpake1bResponse {
            if let sr1 = serverRound1 {
                let full = Bytes.combine(sr1, m.centralChallengeHash)
                serverRound1 = full
                cli.readRound1(full)
            }
            step = .ROUND_1B_RECEIVED
            print("[JpakeAuthBuilder] step -> ROUND_1B_RECEIVED")
        } else if let m = response as? Jpake2Response {
            serverRound2 = m.centralChallengeHash
            cli.readRound2(serverRound2!)
            step = .ROUND_2_RECEIVED
            print("[JpakeAuthBuilder] step -> ROUND_2_RECEIVED")
        } else if let m = response as? Jpake3SessionKeyResponse {
            serverNonce3 = m.deviceKeyNonce
            step = .CONFIRM_3_RECEIVED
            print("[JpakeAuthBuilder] step -> CONFIRM_3_RECEIVED")
        } else if let m = response as? Jpake4KeyConfirmationResponse {
            serverNonce4 = m.nonce
            serverHashDigest4 = m.hashDigest
            step = .CONFIRM_4_RECEIVED
            print("[JpakeAuthBuilder] step -> CONFIRM_4_RECEIVED")
        }
        print("[JpakeAuthBuilder] step(after)=\(step)")
    }

    func generateNonce() -> Data {
        return rand(8)
    }

    enum JpakeStep {
        case BOOTSTRAP_INITIAL
        case ROUND_1A_SENT
        case ROUND_1A_RECEIVED
        case ROUND_1B_SENT
        case ROUND_1B_RECEIVED
        case ROUND_2_SENT
        case ROUND_2_RECEIVED
        case CONFIRM_INITIAL
        case CONFIRM_3_SENT
        case CONFIRM_3_RECEIVED
        case CONFIRM_4_SENT
        case CONFIRM_4_RECEIVED
        case COMPLETE
        case INVALID
    }

    public func done() -> Bool {
        return step == .COMPLETE
    }

    public func invalid() -> Bool {
        return step == .INVALID
    }

    public func getDerivedSecret() -> Data? {
        return derivedSecret
    }

    public func getServerNonce() -> Data? {
        return serverNonce3
    }

    static func defaultRandom(_ count: Int) -> Data {
        return NonBlockingRandom.shared.next(count: count)
    }
}

#endif

private final class NonBlockingRandom {
    static let shared = NonBlockingRandom()

    private let lock = NSLock()
    private let handle: FileHandle?

    private init() {
        handle = FileHandle(forReadingAtPath: "/dev/urandom")
    }

    func next(count: Int) -> Data {
        guard count > 0 else { return Data() }

        if let handle {
            lock.lock()
            defer { lock.unlock() }

            var buffer = Data(capacity: count)
            var remaining = count

            while remaining > 0 {
                do {
                    if let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty {
                        buffer.append(chunk)
                        remaining -= chunk.count
                    } else {
                        break
                    }
                } catch {
                    break
                }
            }

            if buffer.count == count {
                return buffer
            }
        }

        var data = Data(count: count)
        var generator = SystemRandomNumberGenerator()
        for index in 0..<count {
            data[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return data
    }
}
