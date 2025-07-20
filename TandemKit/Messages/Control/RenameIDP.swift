//
//  RenameIDP.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of RenameIDPRequest and RenameIDPResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/RenameIDPRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/RenameIDPResponse.java
//

import Foundation

/// Request to rename an insulin delivery profile.
public class RenameIDPRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-88)),
        size: 19,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var idpId: Int
    public var profileName: String

    public required init(cargo: Data) {
        self.cargo = cargo
        self.idpId = Int(cargo[0])
        self.profileName = Bytes.readString(cargo, 2, 16)
    }

    public init(idpId: Int, profileName: String) {
        self.cargo = Bytes.combine(
            Data([UInt8(idpId & 0xFF)]),
            Data([1]),
            Bytes.writeString(profileName, 16),
            Data([0])
        )
        self.idpId = idpId
        self.profileName = profileName
    }
}

/// Response to a rename profile command.
public class RenameIDPResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-87)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var numberOfProfiles: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.numberOfProfiles = Int(cargo[1])
    }

    public init(status: Int, numberOfProfiles: Int) {
        self.cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([UInt8(numberOfProfiles & 0xFF)])
        )
        self.status = status
        self.numberOfProfiles = numberOfProfiles
    }
}

