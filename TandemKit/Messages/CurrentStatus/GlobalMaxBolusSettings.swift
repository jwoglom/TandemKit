//
//  GlobalMaxBolusSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of GlobalMaxBolusSettingsRequest and GlobalMaxBolusSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/GlobalMaxBolusSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/GlobalMaxBolusSettingsResponse.java
//

import Foundation

/// Request the global maximum bolus settings.
public class GlobalMaxBolusSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: -116,
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

/// Response containing the global maximum bolus settings.
public class GlobalMaxBolusSettingsResponse: Message {
    public static var props = MessageProps(
        opCode: -115,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var maxBolus: Int
    public var maxBolusDefault: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.maxBolus = Bytes.readShort(cargo, 0)
        self.maxBolusDefault = Bytes.readShort(cargo, 2)
    }

    public init(maxBolus: Int, maxBolusDefault: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(maxBolus),
            Bytes.firstTwoBytesLittleEndian(maxBolusDefault)
        )
        self.maxBolus = maxBolus
        self.maxBolusDefault = maxBolusDefault
    }
}

