import Foundation
#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

enum SHA256 {
    static func hash(_ data: Data) -> Data {
        #if canImport(CryptoKit)
            return Data(CryptoKit.SHA256.hash(data: data))
        #else
            return Data(Crypto.SHA256.hash(data: data))
        #endif
    }
}
