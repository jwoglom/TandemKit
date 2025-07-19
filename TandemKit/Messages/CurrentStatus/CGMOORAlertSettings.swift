//
//  CGMOORAlertSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CGMOORAlertSettingsRequest and CGMOORAlertSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CGMOORAlertSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CGMOORAlertSettingsResponse.java
//

import Foundation

/// Request out-of-range CGM alert settings from the pump.
public class CGMOORAlertSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: 94,
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

/// Response describing out-of-range CGM alert configuration.
public class CGMOORAlertSettingsResponse: Message {
    public static var props = MessageProps(
        opCode: 95,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var sensorTimeoutAlertThreshold: Int
    public var sensorTimeoutAlertEnabled: Int
    public var sensorTimeoutDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.sensorTimeoutAlertThreshold = Int(cargo[0])
        self.sensorTimeoutAlertEnabled = Int(cargo[1])
        self.sensorTimeoutDefaultBitmask = Int(cargo[2])
    }

    public init(sensorTimeoutAlertThreshold: Int, sensorTimeoutAlertEnabled: Int, sensorTimeoutDefaultBitmask: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(sensorTimeoutAlertThreshold),
            Bytes.firstByteLittleEndian(sensorTimeoutAlertEnabled),
            Bytes.firstByteLittleEndian(sensorTimeoutDefaultBitmask)
        )
        self.sensorTimeoutAlertThreshold = sensorTimeoutAlertThreshold
        self.sensorTimeoutAlertEnabled = sensorTimeoutAlertEnabled
        self.sensorTimeoutDefaultBitmask = sensorTimeoutDefaultBitmask
    }
}

