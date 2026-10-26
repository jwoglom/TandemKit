import Foundation

public struct PumpState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    public typealias RawValue = [String: Any]

    public var peripheralUuid: String?
    public var pincode: String?
    public var derivedSecret: Data?
    public var serverNonce: Data?
    public var timeSinceReset: UInt32?
    public var apiVersion: ApiVersion?
    public var pumpSerial: UInt32?
    public var modelNumber: UInt32?
    public var controlBitsA: UInt32?
    public var controlBitsB: UInt32?
    public var pcbSerialNumber: UInt32?
    public var softwareName: String?
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
        modelNumber: UInt32? = nil,
        softwareName: String? = nil,
        controlBitsA: UInt32? = nil,
        controlBitsB: UInt32? = nil,
        pcbSerialNumber: UInt32? = nil,
        pumpModel: PumpModel? = nil
    ) {
        self.peripheralUuid = peripheralUuid
        self.derivedSecret = derivedSecret
        self.serverNonce = serverNonce
        self.timeSinceReset = timeSinceReset
        self.apiVersion = apiVersion
        self.pumpSerial = pumpSerial
        self.modelNumber = modelNumber
        self.softwareName = softwareName
        self.controlBitsA = controlBitsA
        self.controlBitsB = controlBitsB
        self.pcbSerialNumber = pcbSerialNumber
        self.pumpModel = pumpModel
    }

    public init(rawValue: RawValue) {
        peripheralUuid = rawValue["peripheralUuid"] as? String
        pincode = rawValue["pincode"] as? String
        derivedSecret = rawValue["derivedSecret"] as? Data
        serverNonce = rawValue["serverNonce"] as? Data
        timeSinceReset = rawValue["timeSinceReset"] as? UInt32
        if let apiVersionRaw = rawValue["apiVersion"] as? ApiVersion.RawValue {
            apiVersion = ApiVersion(rawValue: apiVersionRaw)
        }
        pumpSerial = rawValue["pumpSerial"] as? UInt32
        modelNumber = rawValue["modelNumber"] as? UInt32
        controlBitsA = rawValue["controlBitsA"] as? UInt32
        controlBitsB = rawValue["controlBitsB"] as? UInt32
        softwareName = rawValue["softwareName"] as? String
        pcbSerialNumber = rawValue["pcbSerialNumber"] as? UInt32
        if let pumpModelRaw = rawValue["pumpModel"] as? PumpModel.RawValue {
            pumpModel = PumpModel(rawValue: pumpModelRaw)
        }
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]

        rawValue["peripheralUuid"] = peripheralUuid
        rawValue["pincode"] = pincode
        rawValue["derivedSecret"] = derivedSecret
        rawValue["serverNonce"] = serverNonce
        rawValue["modelNumber"] = modelNumber
        rawValue["softwareName"] = softwareName
        rawValue["controlBitsA"] = controlBitsA
        rawValue["controlBitsB"] = controlBitsB
        rawValue["pcbSerialNumber"] = pcbSerialNumber
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

    func getAuthKey() -> Data {
        if let derivedSecret, let serverNonce {
            return Hkdf.build(nonce: serverNonce, keyMaterial: derivedSecret)
        }

        return Data()
    }

    public var debugDescription: String {
        (["### PumpState"] + debugFields).joined(separator: "\n")
    }

    var debugFields: [String] {
        [
            "* peripheralUuid: \(debugValue(peripheralUuid))",
            "* pincode: \(debugValue(pincode))",
            "* derivedSecret: \(debugValue(derivedSecret?.base64EncodedString()))",
            "* serverNonce: \(debugValue(serverNonce?.base64EncodedString()))",
            "* timeSinceReset: \(debugValue(timeSinceReset))",
            "* apiVersion: \(apiVersion.map { "\($0.major).\($0.minor)" } ?? "nil")",
            "* pumpSerial: \(debugValue(pumpSerial))",
            "* modelNumber: \(debugValue(modelNumber))",
            "* pcbSerialNumber: \(debugValue(pcbSerialNumber))",
            "* softwareName: \(debugValue(softwareName))",
            "* controlBitsA: \(debugValue(controlBitsA))",
            "* controlBitsB: \(debugValue(controlBitsB))",
            "* pumpModel: \(debugValue(pumpModel))"
        ]
    }
}
