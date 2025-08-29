import Foundation

struct HmacSha256 {
    static func hmac(_ data: Data, key: Data) -> Data {
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
        let inner = SHA256.hash(iKey + data)
        let final = SHA256.hash(oKey + inner)
        return final
    }
}

