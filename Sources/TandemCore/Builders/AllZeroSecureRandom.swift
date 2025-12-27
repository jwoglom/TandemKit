import Foundation

/// A SecureRandom-like generator that returns all zero bytes.
enum AllZeroSecureRandom {
    static func nextBytes(count: Int) -> Data {
        Data(repeating: 0, count: count)
    }
}
