import Foundation

public enum JpakeStep {
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

public protocol JpakeProvider: AnyObject {
    typealias RandomBytesGenerator = (Int) -> Data

    var pairingCode: String { get }
    func makeRound1() -> Data
    func readRound1(_ data: Data)
    func makeRound2() -> Data
    func readRound2(_ data: Data)
    func deriveSecret() -> Data
}

public protocol JpakeProviderFactory {
    func make(
        pairingCode: String,
        derivedSecret: Data?,
        random: @escaping JpakeProvider.RandomBytesGenerator
    ) -> JpakeProvider?
}

public struct DefaultJpakeProviderFactory: JpakeProviderFactory {
    public init() {}

    public func make(
        pairingCode: String,
        derivedSecret: Data?,
        random: @escaping JpakeProvider.RandomBytesGenerator
    ) -> JpakeProvider? {
        #if canImport(MbedTLS) && canImport(MbedTLSShim)
            if let provider = try? MbedTLSJpakeProvider(
                pairingCode: pairingCode,
                derivedSecret: derivedSecret,
                rand: random
            ) {
                return provider
            }
        #endif

        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            return SwiftECCJpakeProvider(
                pairingCode: pairingCode,
                derivedSecret: derivedSecret,
                rand: random
            )
        #else
            return nil
        #endif
    }
}
