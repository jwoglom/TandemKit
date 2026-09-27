import Foundation
#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

enum SHA1 {
    static func hash(_ data: Data) -> Data {
        #if canImport(CryptoKit)
            return Data(Insecure.SHA1.hash(data: data))
        #else
            return Data(Crypto.Insecure.SHA1.hash(data: data))
        #endif
    }
}
