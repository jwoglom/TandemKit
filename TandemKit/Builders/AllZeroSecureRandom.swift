import Foundation

/// A SecureRandom-like generator that returns all zero bytes.
struct AllZeroSecureRandom {
    static func nextBytes(count: Int) -> Data {
        return Data(repeating: 0, count: count)
    }
}
