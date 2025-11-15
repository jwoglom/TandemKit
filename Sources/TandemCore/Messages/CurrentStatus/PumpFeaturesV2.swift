import Foundation

/// Request additional pump feature information (API 2.5+).
public class PumpFeaturesV2Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-96)),
        size: 1,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init(input: Int = 2) {
        cargo = Bytes.firstByteLittleEndian(input)
    }
}

/// Response describing supported pump feature sets.
public class PumpFeaturesV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-95)),
        size: 6,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var status: Int
    public var supportedFeatureIndexId: Int
    public var pumpFeaturesBitmask: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        supportedFeatureIndexId = Int(cargo[1])
        pumpFeaturesBitmask = Bytes.readUint32(cargo, 2)
    }

    public init(status: Int, supportedFeatureIndex: Int, pumpFeaturesBitmask: UInt32) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstByteLittleEndian(supportedFeatureIndex),
            Bytes.toUint32(pumpFeaturesBitmask)
        )
        self.status = status
        supportedFeatureIndexId = supportedFeatureIndex
        self.pumpFeaturesBitmask = pumpFeaturesBitmask
    }

    /// Supported feature index values.
    public enum SupportedFeatureIndex: Int {
        case mainFeatures = 0
        case ciqProFeatures = 1
        case controlFeatures = 3
    }

    public var supportedFeatureIndex: SupportedFeatureIndex? {
        SupportedFeatureIndex(rawValue: supportedFeatureIndexId)
    }

    /// Decode primary features when index == mainFeatures.
    public var primaryFeatures: Set<PumpFeaturesV1Response.PumpFeatureType>? {
        guard supportedFeatureIndex == .mainFeatures else { return nil }
        return PumpFeaturesV1Response.PumpFeatureType.fromBitmask(UInt64(pumpFeaturesBitmask))
    }
}
