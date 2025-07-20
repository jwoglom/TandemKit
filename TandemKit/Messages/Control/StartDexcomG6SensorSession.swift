//
//  StartDexcomG6SensorSession.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of StartDexcomG6SensorSessionRequest and StartDexcomG6SensorSessionResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/StartDexcomG6SensorSessionRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/StartDexcomG6SensorSessionResponse.java
//

import Foundation

/// Request to start a Dexcom G6 sensor session.
public class StartDexcomG6SensorSessionRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-78)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var sensorCode: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.sensorCode = Bytes.readShort(cargo, 0)
    }

    public init(sensorCode: Int = 0) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(sensorCode)
        self.sensorCode = sensorCode
    }
}

/// Response after starting a Dexcom G6 sensor session.
public class StartDexcomG6SensorSessionResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-77)),
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

