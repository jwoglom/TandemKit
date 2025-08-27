//
//  StopDexcomCGMSensorSession.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of StopDexcomCGMSensorSessionRequest and StopDexcomCGMSensorSessionResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/StopDexcomCGMSensorSessionRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/StopDexcomCGMSensorSessionResponse.java
//

import Foundation

/// Request to stop an active Dexcom CGM sensor session.
public class StopDexcomCGMSensorSessionRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-76)),
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

/// Response to stopping the Dexcom CGM session.
public class StopDexcomCGMSensorSessionResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-75)),
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

