//
//  SetIDPSegment.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetIDPSegmentRequest and SetIDPSegmentResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetIDPSegmentRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetIDPSegmentResponse.java
//

import Foundation

/// Request to modify a single segment within an insulin delivery profile.
public class SetIDPSegmentRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-86)),
        size: 17,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var idpId: Int
    public var unknownId: Int
    public var segmentIndex: Int
    public var operationId: Int
    public var profileStartTime: Int
    public var profileBasalRate: Int
    public var profileCarbRatio: UInt32
    public var profileTargetBG: Int
    public var profileISF: Int
    public var idpStatusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.idpId = Int(cargo[0])
        self.unknownId = Int(cargo[1])
        self.segmentIndex = Int(cargo[2])
        self.operationId = Int(cargo[3])
        self.profileStartTime = Bytes.readShort(cargo, 4)
        self.profileBasalRate = Bytes.readShort(cargo, 6)
        self.profileCarbRatio = Bytes.readUint32(cargo, 8)
        self.profileTargetBG = Bytes.readShort(cargo, 12)
        self.profileISF = Bytes.readShort(cargo, 14)
        self.idpStatusId = Int(cargo[16])
    }

    public init(idpId: Int, unknownId: Int, segmentIndex: Int, operation: IDPSegmentOperation, profileStartTime: Int, profileBasalRate: Int, profileCarbRatio: UInt32, profileTargetBG: Int, profileISF: Int, idpStatusId: Int) {
        self.cargo = SetIDPSegmentRequest.buildCargo(idpId: idpId, unknownId: unknownId, segmentIndex: segmentIndex, operationId: operation.rawValue, profileStartTime: profileStartTime, profileBasalRate: profileBasalRate, profileCarbRatio: profileCarbRatio, profileTargetBG: profileTargetBG, profileISF: profileISF, idpStatusId: idpStatusId)
        self.idpId = idpId
        self.unknownId = unknownId
        self.segmentIndex = segmentIndex
        self.operationId = operation.rawValue
        self.profileStartTime = profileStartTime
        self.profileBasalRate = profileBasalRate
        self.profileCarbRatio = profileCarbRatio
        self.profileTargetBG = profileTargetBG
        self.profileISF = profileISF
        self.idpStatusId = idpStatusId
    }

    public static func buildCargo(idpId: Int, unknownId: Int, segmentIndex: Int, operationId: Int, profileStartTime: Int, profileBasalRate: Int, profileCarbRatio: UInt32, profileTargetBG: Int, profileISF: Int, idpStatusId: Int) -> Data {
        return Bytes.combine(
            Data([UInt8(idpId & 0xFF), UInt8(unknownId & 0xFF)]),
            Data([UInt8(segmentIndex & 0xFF), UInt8(operationId & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(profileStartTime),
            Bytes.firstTwoBytesLittleEndian(profileBasalRate),
            Bytes.toUint32(profileCarbRatio),
            Bytes.firstTwoBytesLittleEndian(profileTargetBG),
            Bytes.firstTwoBytesLittleEndian(profileISF),
            Data([UInt8(idpStatusId & 0xFF)])
        )
    }

    public enum IDPSegmentOperation: Int {
        case modifySegmentId = 0
        case createSegment = 1
        case deleteSegmentId = 2
    }

    public var operation: IDPSegmentOperation? { IDPSegmentOperation(rawValue: operationId) }
    public var idpStatus: Set<IDPSegmentResponse.IDPSegmentStatus> { IDPSegmentResponse.IDPSegmentStatus.fromBitmask(idpStatusId) }
}

/// Response indicating status of segment update.
public class SetIDPSegmentResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-85)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int
    public var unknown: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.unknown = Int(cargo[1])
    }

    public init(status: Int, unknown: Int) {
        self.cargo = Data([UInt8(status & 0xFF), UInt8(unknown & 0xFF)])
        self.status = status
        self.unknown = unknown
    }
}

