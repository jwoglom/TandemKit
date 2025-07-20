//
//  CreateIDP.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CreateIDPRequest and CreateIDPResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/CreateIDPRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/CreateIDPResponse.java
//

import Foundation

/// Request to create or duplicate an insulin delivery profile.
public class CreateIDPRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-26)),
        size: 35,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var profileName: String
    public var firstSegmentProfileCarbRatio: Int
    public var firstSegmentProfileBasalRate: Int
    public var firstSegmentProfileTargetBG: Int
    public var firstSegmentProfileISF: Int
    public var profileInsulinDuration: Int
    public var profileCarbEntry: Int
    public var sourceIdpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.profileName = Bytes.readString(cargo, 0, 16)
        self.firstSegmentProfileCarbRatio = Bytes.readShort(cargo, 17)
        self.firstSegmentProfileBasalRate = Bytes.readShort(cargo, 23)
        self.firstSegmentProfileTargetBG = Bytes.readShort(cargo, 25)
        self.firstSegmentProfileISF = Bytes.readShort(cargo, 27)
        self.profileInsulinDuration = Bytes.readShort(cargo, 29)
        self.sourceIdpId = Int(cargo[33])
        self.profileCarbEntry = Int(cargo[34])
    }

    /// Create a brand new profile.
    public init(profileName: String, firstSegmentProfileCarbRatio: Int, firstSegmentProfileBasalRate: Int, firstSegmentProfileTargetBG: Int, firstSegmentProfileISF: Int, profileInsulinDuration: Int, profileCarbEntry: Int) {
        self.cargo = CreateIDPRequest.buildCargo(name: profileName, firstSegmentProfileCarbRatio: firstSegmentProfileCarbRatio, firstSegmentProfileBasalRate: firstSegmentProfileBasalRate, firstSegmentProfileTargetBG: firstSegmentProfileTargetBG, firstSegmentProfileISF: firstSegmentProfileISF, profileInsulinDuration: profileInsulinDuration, carbEntry: profileCarbEntry, sourceIdpId: -1)
        self.profileName = profileName
        self.firstSegmentProfileCarbRatio = firstSegmentProfileCarbRatio
        self.firstSegmentProfileBasalRate = firstSegmentProfileBasalRate
        self.firstSegmentProfileTargetBG = firstSegmentProfileTargetBG
        self.firstSegmentProfileISF = firstSegmentProfileISF
        self.profileInsulinDuration = profileInsulinDuration
        self.profileCarbEntry = profileCarbEntry
        self.sourceIdpId = -1
    }

    /// Duplicate an existing profile by ID.
    public init(profileName: String, sourceIdpId: Int) {
        self.cargo = CreateIDPRequest.buildCargo(name: profileName, firstSegmentProfileCarbRatio: 0, firstSegmentProfileBasalRate: 0, firstSegmentProfileTargetBG: 0, firstSegmentProfileISF: 0, profileInsulinDuration: 0, carbEntry: 0, sourceIdpId: sourceIdpId)
        self.profileName = profileName
        self.firstSegmentProfileCarbRatio = 0
        self.firstSegmentProfileBasalRate = 0
        self.firstSegmentProfileTargetBG = 0
        self.firstSegmentProfileISF = 0
        self.profileInsulinDuration = 0
        self.profileCarbEntry = 0
        self.sourceIdpId = sourceIdpId
    }

    public static func buildCargo(name: String, firstSegmentProfileCarbRatio: Int, firstSegmentProfileBasalRate: Int, firstSegmentProfileTargetBG: Int, firstSegmentProfileISF: Int, profileInsulinDuration: Int, carbEntry: Int, sourceIdpId: Int) -> Data {
        return Bytes.combine(
            Bytes.writeString(name, 17),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileCarbRatio),
            Data([0,0]),
            Data([0,0]),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileBasalRate),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileTargetBG),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileISF),
            Bytes.firstTwoBytesLittleEndian(profileInsulinDuration),
            sourceIdpId == -1 ? Data([31,5]) : Data([0,0]),
            Data([UInt8(sourceIdpId & 0xFF)]),
            Data([UInt8(carbEntry & 0xFF)])
        )
    }
}

/// Response indicating status of profile creation.
public class CreateIDPResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-25)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var newIdpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.newIdpId = Int(cargo[1])
    }

    public init(status: Int, newIdpId: Int) {
        self.cargo = Data([UInt8(status & 0xFF), UInt8(newIdpId & 0xFF)])
        self.status = status
        self.newIdpId = newIdpId
    }
}

