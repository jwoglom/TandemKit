//
//  Localization.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of LocalizationRequest and LocalizationResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/LocalizationRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/LocalizationResponse.java
//

import Foundation

/// Request pump localization settings.
public class LocalizationRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-90)),
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

/// Response containing localization preferences.
public class LocalizationResponse: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-89)),
        size: 7,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var glucoseOUM: Int
    public var regionSetting: Int
    public var languageSelected: Int
    public var languagesAvailableBitmask: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.glucoseOUM = Int(cargo[0])
        self.regionSetting = Int(cargo[1])
        self.languageSelected = Int(cargo[2])
        self.languagesAvailableBitmask = Bytes.readUint32(cargo, 3)
    }

    public init(glucoseOUM: Int, regionSetting: Int, languageSelected: Int, languagesAvailableBitmask: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(glucoseOUM),
            Bytes.firstByteLittleEndian(regionSetting),
            Bytes.firstByteLittleEndian(languageSelected),
            Bytes.toUint32(languagesAvailableBitmask)
        )
        self.glucoseOUM = glucoseOUM
        self.regionSetting = regionSetting
        self.languageSelected = languageSelected
        self.languagesAvailableBitmask = languagesAvailableBitmask
    }
}

