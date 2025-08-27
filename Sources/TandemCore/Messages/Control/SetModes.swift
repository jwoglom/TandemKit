//
//  SetModes.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetModesRequest and SetModesResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetModesRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetModesResponse.java
//

import Foundation

/// Request to enable or disable pump modes like sleep or exercise.
public class SetModesRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-52)),
        size: 1,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var bitmap: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bitmap = Int(cargo[0])
    }

    public init(bitmap: Int) {
        self.cargo = Data([UInt8(bitmap & 0xFF)])
        self.bitmap = bitmap
    }

    public convenience init(command: ModeCommand) {
        self.init(bitmap: command.rawValue)
    }

    public var command: ModeCommand? { ModeCommand(rawValue: bitmap) }

    /// Commands that can be issued via SetModes.
    public enum ModeCommand: Int {
        case sleepModeOn = 1
        case sleepModeOff = 2
        case exerciseModeOn = 3
        case exerciseModeOff = 4
    }
}

/// Response confirming mode changes.
public class SetModesResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-51)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
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

