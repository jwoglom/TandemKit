import Foundation

/// Request additional pump feature information (API 2.5+).
public class PumpFeaturesV2Request: PumpRequest {
    public typealias Response = PumpFeaturesV2Response

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-96)),
        size: 1,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init(input: Int = 2) {
        cargo = Bytes.firstByteLittleEndian(input)
    }

    public init(supportedFeature: PumpFeaturesV2Response.SupportedFeatureIndex) {
        cargo = Bytes.firstByteLittleEndian(supportedFeature.rawValue)
    }

    public var description: String {
        "PumpFeaturesV2Request(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response describing supported pump feature sets (API 2.5+).
public class PumpFeaturesV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-95)),
        size: 6,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
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

    /// Feature index values that indicate which feature set the bitmask encodes.
    public enum SupportedFeatureIndex: Int {
        case mainFeatures = 0
        case ciqProFeatures = 1
        case controlFeatures = 2
        case controlIqFeatures = 3
        case dexcomFeatures = 4
        case abbottFeatures = 5
        case secondaryFeatures = 6
    }

    public var supportedFeatureIndex: SupportedFeatureIndex? {
        SupportedFeatureIndex(rawValue: supportedFeatureIndexId)
    }

    // MARK: - Decoded feature accessors

    /// Primary pump features when index == mainFeatures.
    public var primaryFeatures: Set<PumpFeaturesV1Response.PumpFeatureType>? {
        guard supportedFeatureIndex == .mainFeatures else { return nil }
        return PumpFeaturesV1Response.PumpFeatureType.fromBitmask(UInt64(pumpFeaturesBitmask))
    }

    /// Control-IQ Pro features when index == ciqProFeatures.
    public var controlIqProFeatures: Set<ControlIqProFeatureType>? {
        guard supportedFeatureIndex == .ciqProFeatures else { return nil }
        return ControlIqProFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    /// Control features when index == controlFeatures.
    public var controlFeatures: Set<ControlFeatureType>? {
        guard supportedFeatureIndex == .controlFeatures else { return nil }
        return ControlFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    /// Control-IQ features when index == controlIqFeatures.
    public var controlIqFeatures: Set<ControlIqFeatureType>? {
        guard supportedFeatureIndex == .controlIqFeatures else { return nil }
        return ControlIqFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    /// Dexcom CGM features when index == dexcomFeatures.
    public var dexcomFeatures: Set<DexcomFeatureType>? {
        guard supportedFeatureIndex == .dexcomFeatures else { return nil }
        return DexcomFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    /// Abbott CGM features when index == abbottFeatures.
    public var abbottFeatures: Set<AbbottFeatureType>? {
        guard supportedFeatureIndex == .abbottFeatures else { return nil }
        return AbbottFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    /// Secondary pump features when index == secondaryFeatures.
    public var secondaryFeatures: Set<SecondaryFeatureType>? {
        guard supportedFeatureIndex == .secondaryFeatures else { return nil }
        return SecondaryFeatureType.fromBitmask(pumpFeaturesBitmask)
    }

    // MARK: - Feature type enumerations

    public enum ControlIqProFeatureType: UInt32, CaseIterable {
        case bleControl = 1
        case guiChanges = 2
        case rangeChanges = 4
        case nvmParam = 8
        case extendedBolusDuration = 16
        case autoBolus = 32

        public static func fromBitmask(_ bitmask: UInt32) -> Set<ControlIqProFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public enum ControlFeatureType: UInt32, CaseIterable {
        case changeCartridgeControl = 1
        case basalDeliveryControl = 2
        case standardBolusControl = 4
        case extendedBolusControl = 8
        case tempRateControl = 16
        case cgmControl = 32
        case aamControl = 64
        case shelfModeControl = 128
        case idpControl = 256
        case ledPatternControl = 512
        case unregisterControl = 1024
        case pumpTimeControl = 2048
        case plgsControl = 4096
        case tzControl = 8192
        case reminderSettingsControl = 16384
        case alertSettingsControl = 32768
        case annumControl = 65536
        case aamNotifyMeOnControl = 131_072
        case pumpGlobalSettingsControl = 262_144
        case factoryConfigControl = 524_288
        case snoozeSettingsControl = 1_048_576
        case updatedSettingsQeControl = 2_097_152
        case findMyPumpControl = 4_194_304
        case bolusOverflowControl = 8_388_608
        case preflightControl = 16_777_216
        case userInteractionControl = 33_554_432
        case bloodGlucoseEntryControl = 67_108_864
        case hlogCreatorControl = 134_217_728
        case featureManagement = 268_435_456
        case mobiResearchPump = 536_870_912
        case tipsControlGenericTest = 1_073_741_824

        public static func fromBitmask(_ bitmask: UInt32) -> Set<ControlFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public enum ControlIqFeatureType: UInt32, CaseIterable {
        case timedExercise = 1
        case controlIqVersionOneFive = 256
        case tempRateEnabled = 512
        case extendedBolusEnabled = 2048

        public static func fromBitmask(_ bitmask: UInt32) -> Set<ControlIqFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public enum DexcomFeatureType: UInt32, CaseIterable {
        case g5Cgm = 1
        case g6Cgm = 2
        case g7Cgm = 4
        case autoCal = 8
        case disableGraphSmoothing = 16

        public static func fromBitmask(_ bitmask: UInt32) -> Set<DexcomFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public enum AbbottFeatureType: UInt32, CaseIterable {
        case isFsl2 = 1

        public static func fromBitmask(_ bitmask: UInt32) -> Set<AbbottFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public enum SecondaryFeatureType: UInt32, CaseIterable {
        case baselineProfiles = 1
        case multiCgm = 2
        case bleTdu = 4

        public static func fromBitmask(_ bitmask: UInt32) -> Set<SecondaryFeatureType> {
            Set(allCases.filter { (bitmask & $0.rawValue) != 0 })
        }
    }

    public var description: String {
        "PumpFeaturesV2Response(cargo=\(cargo.hexadecimalString), status=\(status), supportedFeatureIndex=\(String(describing: supportedFeatureIndex)), supportedFeatureIndexId=\(supportedFeatureIndexId), pumpFeaturesBitmask=\(pumpFeaturesBitmask))"
    }
}
