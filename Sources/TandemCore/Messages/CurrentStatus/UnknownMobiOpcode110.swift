//
//  UnknownMobiOpcode110.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of UnknownMobiOpcode110Request and UnknownMobiOpcode110Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/UnknownMobiOpcode110Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/UnknownMobiOpcode110Response.java
//

import Foundation

/// Unknown MOBI opcode 110 request.
public class UnknownMobiOpcode110Request: Message {
    public static let props = MessageProps(
        opCode: 110,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Unknown MOBI opcode 110 response.
public class UnknownMobiOpcode110Response: Message {
    public static let props = MessageProps(
        opCode: 111,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

