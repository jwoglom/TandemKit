import Foundation

public struct PumpState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    public typealias RawValue = [String: Any]

    public let address: UInt32
    public var derivedSecret: Data?
    public var serverNonce: Data?

    public init(address: UInt32, derivedSecret: Data? = nil, serverNonce: Data? = nil) {
        self.address = address
        self.derivedSecret = derivedSecret
        self.serverNonce = serverNonce
    }

    public init() {
        self.init(address: 0, derivedSecret: nil, serverNonce: nil)
    }

    public init?(rawValue: RawValue) {
        guard let address = rawValue["address"] as? UInt32
        else { return nil }

        self.address = address
        derivedSecret = rawValue["derivedSecret"] as? Data
        serverNonce = rawValue["serverNonce"] as? Data
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "address": address
        ]

        rawValue["derivedSecret"] = derivedSecret
        rawValue["serverNonce"] = serverNonce

        return rawValue
    }

    public var debugDescription: String {
        [
            "### PumpState",
            "* address: \(String(format: "%04X", address))",
            "* hasDerivedSecret: \(derivedSecret != nil)",
            "* hasServerNonce: \(serverNonce != nil)"
        ].joined(separator: "\n")
    }
}
