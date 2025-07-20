//
//  DeleteIDP.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of DeleteIDPRequest and DeleteIDPResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/DeleteIDPRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/DeleteIDPResponse.java
//

import Foundation

/// Request to remove an insulin delivery profile.
public class DeleteIDPRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-82)),
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

/// Response after deleting a profile.
public class DeleteIDPResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-81)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var deletedIdpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.deletedIdpId = Int(cargo[1])
    }

    public init(status: Int, deletedIdpId: Int) {
        self.cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([UInt8(deletedIdpId & 0xFF)])
        )
        self.status = status
        self.deletedIdpId = deletedIdpId
    }
}

