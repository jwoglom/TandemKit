//
//  PumpFeaturesV1.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of PumpFeaturesV1Request and PumpFeaturesV1Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/PumpFeaturesV1Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/PumpFeaturesV1Response.java
//

import Foundation

/// Request the primary pump features bitmask.
public class PumpFeaturesV1Request: Message {
    public static let props = MessageProps(
        opCode: 78,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response containing a bitmask of primary pump features.
public class PumpFeaturesV1Response: Message {
    public static let props = MessageProps(
        opCode: 79,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var features: Set<PumpFeatureType>

    public required init(cargo: Data) {
        self.cargo = cargo
        self.intMap = Bytes.readUint64(cargo, 0)
        self.features = PumpFeatureType.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        self.cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        self.features = PumpFeatureType.fromBitmask(intMap)
    }

    /// Pump feature bit positions.
    public enum PumpFeatureType: UInt64, CaseIterable {
        case DEXCOM_G5_SUPPORTED = 1
        case DEXCOM_G6_SUPPORTED = 2
        case BASAL_IQ_SUPPORTED = 4
        case CONTROL_IQ_SUPPORTED = 1024
        case WOMBAT_SUPPORTED = 65536
        case BASAL_LIMIT_SUPPORTED = 262144
        case AUTO_POP_SUPPORTED = 33554432
        case BLE_PUMP_CONTROL_SUPPORTED = 268435456
        case PUMP_SETTINGS_IN_IDP_GUI_SUPPORTED = 536870912

        /// Decode a set of pump features from the bitmask.
        public static func fromBitmask(_ bitmask: UInt64) -> Set<PumpFeatureType> {
            var set = Set<PumpFeatureType>()
            for f in PumpFeatureType.allCases {
                if (bitmask & f.rawValue) != 0 {
                    set.insert(f)
                }
            }
            return set
        }
    }

    /// Convenience accessor for the set of primary features.
    public var primaryFeatures: Set<PumpFeatureType> { return features }
}

