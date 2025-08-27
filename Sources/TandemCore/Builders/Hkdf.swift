import Foundation

#if canImport(CryptoKit)
import CryptoKit

struct Hkdf {
    static func build(nonce: Data, keyMaterial: Data) -> Data {
        let key = SymmetricKey(data: keyMaterial)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: nonce,
            info: Data(),
            outputByteCount: 32
        )
        return Data(derived.withUnsafeBytes { Data($0) })
    }
}
#endif
