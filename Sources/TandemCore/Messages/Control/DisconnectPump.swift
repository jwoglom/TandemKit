//
//  DisconnectPump.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of DisconnectPumpRequest and DisconnectPumpResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/DisconnectPumpRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/DisconnectPumpResponse.java
//

import Foundation

/// Request to disconnect the pump from the paired device.
public class DisconnectPumpRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-66)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response indicating pump disconnect status.
public class DisconnectPumpResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-65)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
    }

    public init(status: Int) {
        self.cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}

