import Foundation

public struct PumpState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    public typealias RawValue = [String: Any]

    public var peripheralUuid: String?
    public var derivedSecret: Data?
    public var serverNonce: Data?
    public var timeSinceReset: UInt32?

    public var valid: Bool {
        peripheralUuid != nil && derivedSecret != nil && serverNonce != nil
    }

    public init(
        peripheralUuid: String? = nil,
        derivedSecret: Data? = nil,
        serverNonce: Data? = nil,
        timeSinceReset: UInt32? = nil
    ) {
        self.peripheralUuid = peripheralUuid
        self.derivedSecret = derivedSecret
        self.serverNonce = serverNonce
        self.timeSinceReset = timeSinceReset
    }

    public init() {
        self.init(peripheralUuid: nil, derivedSecret: nil, serverNonce: nil, timeSinceReset: nil)
    }

    public init?(rawValue: RawValue) {
        guard let peripheralUuid = rawValue["peripheralUuid"] as? String
        else { return nil }

        self.peripheralUuid = peripheralUuid
        derivedSecret = rawValue["derivedSecret"] as? Data
        serverNonce = rawValue["serverNonce"] as? Data
        timeSinceReset = rawValue["timeSinceReset"] as? UInt32
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]

        rawValue["peripheralUuid"] = peripheralUuid
        rawValue["derivedSecret"] = derivedSecret
        rawValue["serverNonce"] = serverNonce
        rawValue["timeSinceReset"] = timeSinceReset

        return rawValue
    }

    public var debugDescription: String {
        [
            "### PumpState",
            "* peripheralUuid: \(String(describing: peripheralUuid))",
            "* derivedSecret: \(String(describing: derivedSecret?.base64EncodedString()))",
            "* serverNonce: \(String(describing: serverNonce?.base64EncodedString()))",
            "* timeSinceReset: \(String(describing: timeSinceReset))"
        ].joined(separator: "\n")
    }
}
