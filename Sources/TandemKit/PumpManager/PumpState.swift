import Foundation
import TandemCore

public struct PumpState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    public typealias RawValue = [String: Any]

    public var peripheralUuid: String?
    public var derivedSecret: Data?
    public var serverNonce: Data?
    public var timeSinceReset: UInt32?
    public var apiVersion: ApiVersion?
    public var pumpSerial: UInt32?
    public var pumpModel: PumpModel?
    

    // other fields are technically not required by other parts of the driver
    public var valid: Bool {
        peripheralUuid != nil && derivedSecret != nil && serverNonce != nil
    }

    public init(
        peripheralUuid: String? = nil,
        derivedSecret: Data? = nil,
        serverNonce: Data? = nil,
        timeSinceReset: UInt32? = nil,
        apiVersion: ApiVersion? = nil,
        pumpSerial: UInt32? = nil,
        pumpModel: PumpModel? = nil
    ) {
        self.peripheralUuid = peripheralUuid
        self.derivedSecret = derivedSecret
        self.serverNonce = serverNonce
        self.timeSinceReset = timeSinceReset
        self.apiVersion = apiVersion
        self.pumpSerial = pumpSerial
        self.pumpModel = pumpModel
    }

    public init() {
        self.init(peripheralUuid: nil, derivedSecret: nil, serverNonce: nil, timeSinceReset: nil, apiVersion: nil, pumpSerial: nil, pumpModel: nil)
    }

    public init?(rawValue: RawValue) {
        guard let peripheralUuid = rawValue["peripheralUuid"] as? String
        else { return nil }

        self.peripheralUuid = peripheralUuid
        derivedSecret = rawValue["derivedSecret"] as? Data
        serverNonce = rawValue["serverNonce"] as? Data
        timeSinceReset = rawValue["timeSinceReset"] as? UInt32
        
        if let apiVersionRaw = rawValue["apiVersion"] as? ApiVersion.RawValue {
            apiVersion = ApiVersion(rawValue: apiVersionRaw)
        }
        pumpSerial = rawValue["pumpSerial"] as? UInt32
        if let pumpModelRaw = rawValue["pumpModel"] as? PumpModel.RawValue {
            pumpModel = PumpModel(rawValue: pumpModelRaw)
        }
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]

        rawValue["peripheralUuid"] = peripheralUuid
        rawValue["derivedSecret"] = derivedSecret
        rawValue["serverNonce"] = serverNonce
        if let timeSinceReset = timeSinceReset {
            rawValue["timeSinceReset"] = timeSinceReset
        }
        if let apiVersion = apiVersion {
            rawValue["apiVersion"] = apiVersion.rawValue
        }
        if let pumpSerial = pumpSerial {
            rawValue["pumpSerial"] = pumpSerial
        }
        if let pumpModel = pumpModel {
            rawValue["pumpModel"] = pumpModel.rawValue
        }

        return rawValue
    }

    public var debugDescription: String {
        [
            "### PumpState",
            "* peripheralUuid: \(String(describing: peripheralUuid))",
            "* derivedSecret: \(String(describing: derivedSecret?.base64EncodedString()))",
            "* serverNonce: \(String(describing: serverNonce?.base64EncodedString()))",
            "* timeSinceReset: \(String(describing: timeSinceReset))",
            "* apiVersion: \(String(describing: apiVersion))",
            "* pumpSerial: \(String(describing: pumpSerial))",
            "* pumpModel: \(String(describing: pumpModel))",
        ].joined(separator: "\n")
    }
}
