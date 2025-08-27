//
//  HomeScreenMirror.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of HomeScreenMirrorRequest and HomeScreenMirrorResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/HomeScreenMirrorRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/HomeScreenMirrorResponse.java
//

import Foundation

/// Request basic home screen status info.
public class HomeScreenMirrorRequest: Message {
    public static let props = MessageProps(
        opCode: 56,
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

/// Response mirroring the pump home screen icons.
public class HomeScreenMirrorResponse: Message {
    public static let props = MessageProps(
        opCode: 57,
        size: 9,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var cgmTrendIconId: Int
    public var cgmAlertIconId: Int
    public var statusIcon0Id: Int
    public var statusIcon1Id: Int
    public var bolusStatusIconId: Int
    public var basalStatusIconId: Int
    public var apControlStateIconId: Int
    public var remainingInsulinPlusIcon: Bool
    public var cgmDisplayData: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        self.cgmTrendIconId = Int(cargo[0])
        self.cgmAlertIconId = Int(cargo[1])
        self.statusIcon0Id = Int(cargo[2])
        self.statusIcon1Id = Int(cargo[3])
        self.bolusStatusIconId = Int(cargo[4])
        self.basalStatusIconId = Int(cargo[5])
        self.apControlStateIconId = Int(cargo[6])
        self.remainingInsulinPlusIcon = cargo[7] != 0
        self.cgmDisplayData = cargo[8] != 0
    }

    public init(cgmTrendIconId: Int, cgmAlertIconId: Int, statusIcon0Id: Int, statusIcon1Id: Int, bolusStatusIconId: Int, basalStatusIconId: Int, apControlStateIconId: Int, remainingInsulinPlusIcon: Bool, cgmDisplayData: Bool) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(cgmTrendIconId),
            Bytes.firstByteLittleEndian(cgmAlertIconId),
            Bytes.firstByteLittleEndian(statusIcon0Id),
            Bytes.firstByteLittleEndian(statusIcon1Id),
            Bytes.firstByteLittleEndian(bolusStatusIconId),
            Bytes.firstByteLittleEndian(basalStatusIconId),
            Bytes.firstByteLittleEndian(apControlStateIconId),
            Bytes.firstByteLittleEndian(remainingInsulinPlusIcon ? 1 : 0),
            Bytes.firstByteLittleEndian(cgmDisplayData ? 1 : 0)
        )
        self.cgmTrendIconId = cgmTrendIconId
        self.cgmAlertIconId = cgmAlertIconId
        self.statusIcon0Id = statusIcon0Id
        self.statusIcon1Id = statusIcon1Id
        self.bolusStatusIconId = bolusStatusIconId
        self.basalStatusIconId = basalStatusIconId
        self.apControlStateIconId = apControlStateIconId
        self.remainingInsulinPlusIcon = remainingInsulinPlusIcon
        self.cgmDisplayData = cgmDisplayData
    }
}

