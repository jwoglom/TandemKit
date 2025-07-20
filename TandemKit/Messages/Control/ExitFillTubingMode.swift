//
//  ExitFillTubingMode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ExitFillTubingModeRequest and ExitFillTubingModeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/ExitFillTubingModeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/ExitFillTubingModeResponse.java
//

import Foundation

/// Request to exit fill tubing mode.
public class ExitFillTubingModeRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-106)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response to exit fill tubing mode request.
public class ExitFillTubingModeResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-105)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
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

