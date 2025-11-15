import Foundation
import TandemBLE

public struct MessageTransportState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]
    public var txId: UInt8
    public var authenticationKey: Data?
    public var timeSinceReset: UInt32?

    public init(txId: UInt8, authenticationKey: Data?, timeSinceReset: UInt32?) {
        self.txId = txId
        self.authenticationKey = authenticationKey
        self.timeSinceReset = timeSinceReset
    }

    public init?(rawValue: RawValue) {
        txId = rawValue["txId"] as? UInt8 ?? 0
        authenticationKey = rawValue["authenticationKey"] as? Data
        timeSinceReset = rawValue["timeSinceReset"] as? UInt32
    }

    public var rawValue: RawValue {
        [
            "txId": txId,
            "authenticationKey": authenticationKey as Any,
            "timeSinceReset": timeSinceReset as Any
        ]
    }
}
