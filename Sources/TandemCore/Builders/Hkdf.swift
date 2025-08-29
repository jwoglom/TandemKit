import Foundation

struct Hkdf {
    static func build(nonce: Data, keyMaterial: Data) -> Data {
        // HKDF-Extract
        let prk = HmacSha256.hmac(keyMaterial, key: nonce)

        // HKDF-Expand (info is empty, output 32 bytes)
        var okm = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while okm.count < 32 {
            var input = Data()
            input.append(previous)
            input.append(counter)
            previous = HmacSha256.hmac(input, key: prk)
            okm.append(previous)
            counter &+= 1
        }
        return okm.prefix(32)
    }
}

