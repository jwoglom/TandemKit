//
//  BolusPermissionRelease.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of BolusPermissionReleaseRequest and BolusPermissionReleaseResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/BolusPermissionReleaseRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/BolusPermissionReleaseResponse.java
//

import Foundation

/// Request to release bolus permission for a previously granted bolus.
public class BolusPermissionReleaseRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-16)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var bolusId: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bolusId = Bytes.readUint32(cargo, 0)
    }

    public init(bolusId: UInt32) {
        self.cargo = Bytes.toUint32(bolusId)
        self.bolusId = bolusId
    }
}

/// Response indicating whether bolus permission release succeeded.
public class BolusPermissionReleaseResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-15)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
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

    /// Convenience enumeration for release status.
    public enum ReleaseStatus: Int {
        case success = 0
        case failure = 1
    }

    public var releaseStatus: ReleaseStatus? { ReleaseStatus(rawValue: status) }
}

