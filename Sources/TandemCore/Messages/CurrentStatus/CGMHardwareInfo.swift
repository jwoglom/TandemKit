//
//  CGMHardwareInfo.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CGMHardwareInfoRequest and CGMHardwareInfoResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CGMHardwareInfoRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CGMHardwareInfoResponse.java
//

import Foundation

/// Request CGM hardware information from the pump.
public class CGMHardwareInfoRequest: Message {
    public static let props = MessageProps(
        opCode: 96,
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

/// Response containing CGM hardware information (e.g. transmitter ID).
public class CGMHardwareInfoResponse: Message {
    public static let props = MessageProps(
        opCode: 97,
        size: 17,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var hardwareInfoString: String
    public var lastByte: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.hardwareInfoString = Bytes.readString(cargo, 0, 16)
        self.lastByte = Int(cargo[16])
    }

    public init(hardwareInfoString: String, lastByte: Int) {
        self.cargo = Bytes.combine(
            Bytes.writeString(hardwareInfoString, 16),
            Bytes.firstByteLittleEndian(lastByte)
        )
        self.hardwareInfoString = hardwareInfoString
        self.lastByte = lastByte
    }
}

