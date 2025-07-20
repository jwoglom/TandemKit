import Foundation
import CryptoKit

struct HmacSha256 {
    static func hmac(_ data: Data, key: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }
}
