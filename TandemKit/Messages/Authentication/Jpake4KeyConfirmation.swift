//
//  Jpake4KeyConfirmation.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of Jpake4KeyConfirmationRequest and Jpake4KeyConfirmationResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/Jpake4KeyConfirmationRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/Jpake4KeyConfirmationResponse.java
//

import Foundation

/// Final JPAKE message confirming key derivation.
public class Jpake4KeyConfirmationRequest: Message {
    public static var props = MessageProps(
        opCode: 40,
        size: 50,
        type: .Request,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public static let RESERVED = Data(repeating: 0, count: 8)

    public var cargo: Data
    public var appInstanceId: Int
    public var nonce: Data
    public var reserved: Data
    public var hashDigest: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.nonce = cargo.subdata(in: 2..<10)
        self.reserved = cargo.subdata(in: 10..<18)
        self.hashDigest = cargo.subdata(in: 18..<50)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        precondition(hashDigest.count == 32)
        self.cargo = Jpake4KeyConfirmationRequest.buildCargo(appInstanceId: appInstanceId, nonce: nonce, reserved: reserved, hashDigest: hashDigest)
        self.appInstanceId = appInstanceId
        self.nonce = nonce
        self.reserved = reserved
        self.hashDigest = hashDigest
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved,
            hashDigest
        )
    }
}

/// Response echoing the confirmation data from the pump.
public class Jpake4KeyConfirmationResponse: Message {
    public static var props = MessageProps(
        opCode: 41,
        size: 50,
        type: .Response,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public static let RESERVED = Data(repeating: 0, count: 8)

    public var cargo: Data
    public var appInstanceId: Int
    public var nonce: Data
    public var reserved: Data
    public var hashDigest: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.nonce = cargo.subdata(in: 2..<10)
        self.reserved = cargo.subdata(in: 10..<18)
        self.hashDigest = cargo.subdata(in: 18..<50)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        precondition(hashDigest.count == 32)
        self.cargo = Jpake4KeyConfirmationResponse.buildCargo(appInstanceId: appInstanceId, nonce: nonce, reserved: reserved, hashDigest: hashDigest)
        self.appInstanceId = appInstanceId
        self.nonce = nonce
        self.reserved = reserved
        self.hashDigest = hashDigest
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved,
            hashDigest
        )
    }
}

