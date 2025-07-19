//
//  CGMRateAlertSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CGMRateAlertSettingsRequest and CGMRateAlertSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CGMRateAlertSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CGMRateAlertSettingsResponse.java
//

import Foundation

/// Request CGM rate-of-change alert settings from the pump.
public class CGMRateAlertSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: 92,
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

/// Response describing rate-of-change CGM alert configuration.
public class CGMRateAlertSettingsResponse: Message {
    public static var props = MessageProps(
        opCode: 93,
        size: 6,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var riseRateThreshold: Int
    public var riseRateEnabled: Int
    public var riseRateDefaultBitmask: Int
    public var fallRateThreshold: Int
    public var fallRateEnabled: Int
    public var fallRateDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.riseRateThreshold = Int(cargo[0])
        self.riseRateEnabled = Int(cargo[1])
        self.riseRateDefaultBitmask = Int(cargo[2])
        self.fallRateThreshold = Int(cargo[3])
        self.fallRateEnabled = Int(cargo[4])
        self.fallRateDefaultBitmask = Int(cargo[5])
    }

    public init(riseRateThreshold: Int, riseRateEnabled: Int, riseRateDefaultBitmask: Int, fallRateThreshold: Int, fallRateEnabled: Int, fallRateDefaultBitmask: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(riseRateThreshold),
            Bytes.firstByteLittleEndian(riseRateEnabled),
            Bytes.firstByteLittleEndian(riseRateDefaultBitmask),
            Bytes.firstByteLittleEndian(fallRateThreshold),
            Bytes.firstByteLittleEndian(fallRateEnabled),
            Bytes.firstByteLittleEndian(fallRateDefaultBitmask)
        )
        self.riseRateThreshold = riseRateThreshold
        self.riseRateEnabled = riseRateEnabled
        self.riseRateDefaultBitmask = riseRateDefaultBitmask
        self.fallRateThreshold = fallRateThreshold
        self.fallRateEnabled = fallRateEnabled
        self.fallRateDefaultBitmask = fallRateDefaultBitmask
    }
}

