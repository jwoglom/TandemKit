import Foundation
import CryptoKit

enum SHA256 {
    static func hash(_ data: Data) -> Data {
        return Data(CryptoKit.SHA256.hash(data: data))
    }
}
