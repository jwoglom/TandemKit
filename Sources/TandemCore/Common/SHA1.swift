import Foundation

struct SHA1 {
    private static func rotateLeft(_ value: UInt32, by: UInt32) -> UInt32 {
        (value << by) | (value >> (32 - by))
    }

    static func hash(_ data: Data) -> Data {
        var message = data
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }
        var lengthBytes = Data()
        for i in (0 ..< 8).reversed() {
            lengthBytes.append(UInt8((bitLength >> UInt64(i * 8)) & 0xFF))
        }
        message.append(lengthBytes)

        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        var chunkStart = 0
        while chunkStart < message.count {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0 ..< 16 {
                let index = chunkStart + i * 4
                let word = (UInt32(message[index]) << 24) |
                    (UInt32(message[index + 1]) << 16) |
                    (UInt32(message[index + 2]) << 8) |
                    UInt32(message[index + 3])
                w[i] = word
            }
            for i in 16 ..< 80 { w[i] = rotateLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], by: 1) }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0 ..< 80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0 ..< 20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A82_7999
                case 20 ..< 40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40 ..< 60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                let temp = rotateLeft(a, by: 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotateLeft(b, by: 30)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            chunkStart += 64
        }
        var digest = Data()
        [h0, h1, h2, h3, h4].forEach { h in
            digest.append(UInt8((h >> 24) & 0xFF))
            digest.append(UInt8((h >> 16) & 0xFF))
            digest.append(UInt8((h >> 8) & 0xFF))
            digest.append(UInt8(h & 0xFF))
        }
        return digest
    }
}
