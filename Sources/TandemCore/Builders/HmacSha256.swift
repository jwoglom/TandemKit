import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

struct HmacSha256 {
    static func hmac(_ data: Data, key: Data) -> Data {
#if canImport(CryptoKit)
        let symmetricKey = SymmetricKey(data: key)
        let auth = HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(auth)
#elseif canImport(CommonCrypto)
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyPtr.baseAddress,
                       key.count,
                       dataPtr.baseAddress,
                       data.count,
                       &result)
            }
        }
        return Data(result)
#else
        let blockSize = 64
        var keyData = key
        if keyData.count > blockSize {
            keyData = SHA256.hash(keyData)
        }
        if keyData.count < blockSize {
            keyData.append(contentsOf: [UInt8](repeating: 0, count: blockSize - keyData.count))
        }
        var oKey = Data(repeating: 0x5c, count: blockSize)
        var iKey = Data(repeating: 0x36, count: blockSize)
        for i in 0..<blockSize {
            oKey[i] ^= keyData[i]
            iKey[i] ^= keyData[i]
        }
        let inner = SHA256.hash(Bytes.combine(iKey, data))
        let final = SHA256.hash(Bytes.combine(oKey, inner))
        return final
#endif
    }
}
