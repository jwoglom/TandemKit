//
//  SetActiveIDP.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetActiveIDPRequest and SetActiveIDPResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetActiveIDPRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetActiveIDPResponse.java
//

import Foundation

/// Request to activate an insulin delivery profile.
public class SetActiveIDPRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-20)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var idpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.idpId = Int(cargo[0])
    }

    public init(idpId: Int) {
        self.cargo = Bytes.combine(
            Data([UInt8(idpId & 0xFF)]),
            Data([1])
        )
        self.idpId = idpId
    }
}

/// Response indicating whether the profile was activated.
public class SetActiveIDPResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-19)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
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

