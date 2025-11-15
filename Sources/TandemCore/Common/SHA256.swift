import Foundation
#if canImport(CryptoKit)
    import CryptoKit
#endif

struct SHA256 {
    static func hash(_ data: Data) -> Data {
        #if canImport(CryptoKit)
            return Data(CryptoKit.SHA256.hash(data: data))
        #else
            return softwareHash(data)
        #endif
    }

    #if !canImport(CryptoKit)
        private static let k: [UInt32] = [
            0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
            0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
            0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
            0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
            0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
            0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
            0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
            0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2
        ]

        private static func rotateRight(_ x: UInt32, by: UInt32) -> UInt32 {
            (x >> by) | (x << (32 - by))
        }

        private static func softwareHash(_ data: Data) -> Data {
            var message = data
            let bitLength = UInt64(message.count) * 8
            message.append(0x80)
            while (message.count % 64) != 56 { message.append(0) }
            var lengthBytes = Data()
            for i in (0 ..< 8).reversed() {
                lengthBytes.append(UInt8((bitLength >> UInt64(i * 8)) & 0xFF))
            }
            message.append(lengthBytes)

            var h0: UInt32 = 0x6A09_E667
            var h1: UInt32 = 0xBB67_AE85
            var h2: UInt32 = 0x3C6E_F372
            var h3: UInt32 = 0xA54F_F53A
            var h4: UInt32 = 0x510E_527F
            var h5: UInt32 = 0x9B05_688C
            var h6: UInt32 = 0x1F83_D9AB
            var h7: UInt32 = 0x5BE0_CD19

            var chunkStart = 0
            while chunkStart < message.count {
                var w = [UInt32](repeating: 0, count: 64)
                for i in 0 ..< 16 {
                    let j = chunkStart + i * 4
                    w[i] = (UInt32(message[j]) << 24) |
                        (UInt32(message[j + 1]) << 16) |
                        (UInt32(message[j + 2]) << 8) |
                        UInt32(message[j + 3])
                }
                for i in 16 ..< 64 {
                    let s0 = rotateRight(w[i - 15], by: 7) ^ rotateRight(w[i - 15], by: 18) ^ (w[i - 15] >> 3)
                    let s1 = rotateRight(w[i - 2], by: 17) ^ rotateRight(w[i - 2], by: 19) ^ (w[i - 2] >> 10)
                    w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
                }
                var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
                for i in 0 ..< 64 {
                    let S1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                    let ch = (e & f) ^ ((~e) & g)
                    let temp1 = h &+ S1 &+ ch &+ k[i] &+ w[i]
                    let S0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                    let maj = (a & b) ^ (a & c) ^ (b & c)
                    let temp2 = S0 &+ maj
                    h = g
                    g = f
                    f = e
                    e = d &+ temp1
                    d = c
                    c = b
                    b = a
                    a = temp1 &+ temp2
                }
                h0 &+= a
                h1 &+= b
                h2 &+= c
                h3 &+= d
                h4 &+= e
                h5 &+= f
                h6 &+= g
                h7 &+= h
                chunkStart += 64
            }

            var digest = Data()
            [h0, h1, h2, h3, h4, h5, h6, h7].forEach { h in
                digest.append(UInt8((h >> 24) & 0xFF))
                digest.append(UInt8((h >> 16) & 0xFF))
                digest.append(UInt8((h >> 8) & 0xFF))
                digest.append(UInt8(h & 0xFF))
            }
            return digest
        }
    #endif
}
