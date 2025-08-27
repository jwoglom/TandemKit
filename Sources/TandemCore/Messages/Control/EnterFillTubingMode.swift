//
//  EnterFillTubingMode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of EnterFillTubingModeRequest and EnterFillTubingModeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/EnterFillTubingModeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/EnterFillTubingModeResponse.java
//

import Foundation

/// Request to start fill tubing mode. Pump must be suspended.
public class EnterFillTubingModeRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-108)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response after entering fill tubing mode.
public class EnterFillTubingModeResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-107)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
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

