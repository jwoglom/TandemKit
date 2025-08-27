//
//  BasalIQSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of BasalIQSettingsRequest and BasalIQSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/BasalIQSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/BasalIQSettingsResponse.java
//

import Foundation

/// Request Basal-IQ configuration settings from the pump.
public class BasalIQSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 98,
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

/// Response describing Basal-IQ configuration settings.
public class BasalIQSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 99,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var hypoMinimization: Int
    public var suspendAlert: Int
    public var resumeAlert: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.hypoMinimization = Int(cargo[0])
        self.suspendAlert = Int(cargo[1])
        self.resumeAlert = Int(cargo[2])
    }

    public init(hypoMinimization: Int, suspendAlert: Int, resumeAlert: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(hypoMinimization),
            Bytes.firstByteLittleEndian(suspendAlert),
            Bytes.firstByteLittleEndian(resumeAlert)
        )
        self.hypoMinimization = hypoMinimization
        self.suspendAlert = suspendAlert
        self.resumeAlert = resumeAlert
    }
}

