//
//  BolusPermission.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of BolusPermissionRequest and BolusPermissionResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/BolusPermissionRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/BolusPermissionResponse.java
//

import Foundation

/// Request bolus permission from the pump.
public class BolusPermissionRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-94)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response for bolus permission including bolusId and nack reason.
public class BolusPermissionResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-93)),
        size: 6,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var status: Int
    public var bolusId: Int
    public var nackReasonId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.bolusId = Bytes.readShort(cargo, 1)
        self.nackReasonId = Int(cargo[5])
    }

    public init(status: Int, bolusId: Int, nackReasonId: Int) {
        self.cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0, 0]),
            Data([UInt8(nackReasonId & 0xFF)])
        )
        self.status = status
        self.bolusId = bolusId
        self.nackReasonId = nackReasonId
    }

    public enum NackReason: Int {
        case permissionGranted = 0
        case invalidPumpingState = 1
        case pumpHasPermission = 3
        case mppStateWaitingForResponse = -1
        case mppStateUnknownNackReason = -3
    }

    public var nackReason: NackReason? { NackReason(rawValue: nackReasonId) }

    /// True if permission was granted.
    public var isPermissionGranted: Bool {
        return status == 0 && nackReason == .permissionGranted
    }
}

