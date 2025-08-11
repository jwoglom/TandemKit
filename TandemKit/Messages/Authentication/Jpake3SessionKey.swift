//
//  Jpake3SessionKey.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of Jpake3SessionKeyRequest and Jpake3SessionKeyResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/Jpake3SessionKeyRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/Jpake3SessionKeyResponse.java
//

import Foundation

/// Third JPAKE message triggering session key validation.
public class Jpake3SessionKeyRequest: Message {
    public static var props = MessageProps(
        opCode: 38,
        size: 2,
        type: .Request,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public var cargo: Data
    public var challengeParam: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.challengeParam = Bytes.readShort(cargo, 0)
    }

    public init(challengeParam: Int) {
        self.cargo = Jpake3SessionKeyRequest.buildCargo(challengeParam: challengeParam)
        self.challengeParam = challengeParam
    }

    public static func buildCargo(challengeParam: Int) -> Data {
        return Bytes.firstTwoBytesLittleEndian(challengeParam)
    }
}

/// Response with nonce and reserved values.
public class Jpake3SessionKeyResponse: Message {
    public static var props = MessageProps(
        opCode: 39,
        size: 18,
        type: .Response,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public static let RESERVED = Data(repeating: 0, count: 8)

    public var cargo: Data
    public var appInstanceId: Int
    public var deviceKeyNonce: Data
    public var deviceKeyReserved: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.deviceKeyNonce = cargo.subdata(in: 2..<10)
        self.deviceKeyReserved = cargo.subdata(in: 10..<18)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        self.cargo = Jpake3SessionKeyResponse.buildCargo(appInstanceId: appInstanceId, nonce: nonce, reserved: reserved)
        self.appInstanceId = appInstanceId
        self.deviceKeyNonce = nonce
        self.deviceKeyReserved = reserved
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved
        )
    }
}

