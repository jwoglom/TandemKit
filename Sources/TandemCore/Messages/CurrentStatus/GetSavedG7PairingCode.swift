//
//  GetSavedG7PairingCode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of GetSavedG7PairingCodeRequest and GetSavedG7PairingCodeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/GetSavedG7PairingCodeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/GetSavedG7PairingCodeResponse.java
//

import Foundation

/// Request the saved Dexcom G7 pairing code.
public class GetSavedG7PairingCodeRequest: Message {
    public static let props = MessageProps(
        opCode: 116,
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

/// Response with the saved Dexcom G7 pairing code.
public class GetSavedG7PairingCodeResponse: Message {
    public static let props = MessageProps(
        opCode: 117,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var pairingCode: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.pairingCode = Bytes.readShort(cargo, 0)
    }

    public init(pairingCode: Int) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(pairingCode)
        self.pairingCode = pairingCode
    }
}

