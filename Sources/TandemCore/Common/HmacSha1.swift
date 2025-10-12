import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public func HmacSha1(data: Data, key: Data) -> Data {
#if canImport(CryptoKit)
    let symmetricKey = SymmetricKey(data: key)
    let auth = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey)
    return Data(auth)
#elseif canImport(CommonCrypto)
    var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    key.withUnsafeBytes { keyPtr in
        data.withUnsafeBytes { dataPtr in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                   keyPtr.baseAddress,
                   key.count,
                   dataPtr.baseAddress,
                   data.count,
                   &result)
        }
    }
    return Data(result)
#else
    return HmacSha1Fallback(data: data, key: key)
#endif
}

#if !(canImport(CryptoKit) || canImport(CommonCrypto))
private func HmacSha1Fallback(data: Data, key: Data) -> Data {
    let blockSize = 64
    var keyData = key
    if keyData.count > blockSize {
        keyData = SHA1.hash(keyData)
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
    let innerHash = SHA1.hash(Bytes.combine(iKey, data))
    let finalHash = SHA1.hash(Bytes.combine(oKey, innerHash))
    return finalHash
}
#endif
