//
//  SetG6TransmitterId.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetG6TransmitterIdRequest and SetG6TransmitterIdResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetG6TransmitterIdRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetG6TransmitterIdResponse.java
//

import Foundation

/// Request to configure the G6 transmitter ID on Mobi.
public class SetG6TransmitterIdRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-80)),
        size: 16,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public static let txIdLength = 6

    public var cargo: Data
    public var txId: String

    public required init(cargo: Data) {
        self.cargo = cargo
        self.txId = Bytes.readString(cargo, 0, Self.txIdLength)
    }

    public init(txId: String) {
        self.cargo = Bytes.combine(
            Bytes.writeString(txId, Self.txIdLength),
            Data(repeating: 0, count: 10)
        )
        self.txId = txId
    }
}

/// Response after setting the G6 transmitter ID.
public class SetG6TransmitterIdResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-79)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
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

