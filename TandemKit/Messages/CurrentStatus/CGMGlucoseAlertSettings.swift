//
//  CGMGlucoseAlertSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CGMGlucoseAlertSettingsRequest and CGMGlucoseAlertSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CGMGlucoseAlertSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CGMGlucoseAlertSettingsResponse.java
//

import Foundation

/// Request CGM glucose alert settings from the pump.
public class CGMGlucoseAlertSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: 90,
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

/// Response containing CGM glucose alert configuration.
public class CGMGlucoseAlertSettingsResponse: Message {
    public static var props = MessageProps(
        opCode: 91,
        size: 12,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var highGlucoseAlertThreshold: Int
    public var highGlucoseAlertEnabled: Int
    public var highGlucoseRepeatDuration: Int
    public var highGlucoseAlertDefaultBitmask: Int
    public var lowGlucoseAlertThreshold: Int
    public var lowGlucoseAlertEnabled: Int
    public var lowGlucoseRepeatDuration: Int
    public var lowGlucoseAlertDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.highGlucoseAlertThreshold = Bytes.readShort(cargo, 0)
        self.highGlucoseAlertEnabled = Int(cargo[2])
        self.highGlucoseRepeatDuration = Bytes.readShort(cargo, 3)
        self.highGlucoseAlertDefaultBitmask = Int(cargo[5])
        self.lowGlucoseAlertThreshold = Bytes.readShort(cargo, 6)
        self.lowGlucoseAlertEnabled = Int(cargo[8])
        self.lowGlucoseRepeatDuration = Bytes.readShort(cargo, 9)
        self.lowGlucoseAlertDefaultBitmask = Int(cargo[11])
    }

    public init(highGlucoseAlertThreshold: Int, highGlucoseAlertEnabled: Int, highGlucoseRepeatDuration: Int, highGlucoseAlertDefaultBitmask: Int, lowGlucoseAlertThreshold: Int, lowGlucoseAlertEnabled: Int, lowGlucoseRepeatDuration: Int, lowGlucoseAlertDefaultBitmask: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(highGlucoseAlertThreshold),
            Bytes.firstByteLittleEndian(highGlucoseAlertEnabled),
            Bytes.firstTwoBytesLittleEndian(highGlucoseRepeatDuration),
            Bytes.firstByteLittleEndian(highGlucoseAlertDefaultBitmask),
            Bytes.firstTwoBytesLittleEndian(lowGlucoseAlertThreshold),
            Bytes.firstByteLittleEndian(lowGlucoseAlertEnabled),
            Bytes.firstTwoBytesLittleEndian(lowGlucoseRepeatDuration),
            Bytes.firstByteLittleEndian(lowGlucoseAlertDefaultBitmask)
        )
        self.highGlucoseAlertThreshold = highGlucoseAlertThreshold
        self.highGlucoseAlertEnabled = highGlucoseAlertEnabled
        self.highGlucoseRepeatDuration = highGlucoseRepeatDuration
        self.highGlucoseAlertDefaultBitmask = highGlucoseAlertDefaultBitmask
        self.lowGlucoseAlertThreshold = lowGlucoseAlertThreshold
        self.lowGlucoseAlertEnabled = lowGlucoseAlertEnabled
        self.lowGlucoseRepeatDuration = lowGlucoseRepeatDuration
        self.lowGlucoseAlertDefaultBitmask = lowGlucoseAlertDefaultBitmask
    }
}

