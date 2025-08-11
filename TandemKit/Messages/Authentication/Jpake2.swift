//
//  Jpake2.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of Jpake2Request and Jpake2Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/Jpake2Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/Jpake2Response.java
//

import Foundation

/// Second JPAKE round message.
public class Jpake2Request: Message {
    public static var props = MessageProps(
        opCode: 36,
        size: 167,
        type: .Request,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var centralChallenge: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.centralChallenge = cargo.subdata(in: 2..<167)
    }

    public init(appInstanceId: Int, centralChallenge: Data) {
        precondition(centralChallenge.count == 165)
        self.cargo = Jpake2Request.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }

    public static func buildCargo(appInstanceId: Int, centralChallenge: Data) -> Data {
        var cargo = Bytes.emptyBytes(167)
        let combined = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallenge
        )
        cargo.replaceSubrange(0..<167, with: combined)
        return cargo
    }
}

/// Response to `Jpake2Request` with 168-byte hash.
public class Jpake2Response: Message {
    public static var props = MessageProps(
        opCode: 37,
        size: 170,
        type: .Response,
        characteristic: .AUTHORIZATION_CHARACTERISTICS,
        minApi: .apiV3_2
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var centralChallengeHash: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.centralChallengeHash = cargo.subdata(in: 2..<170)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data) {
        precondition(centralChallengeHash.count == 168)
        self.cargo = Jpake2Response.buildCargo(appInstanceId: appInstanceId, centralChallengeHash: centralChallengeHash)
        self.appInstanceId = appInstanceId
        self.centralChallengeHash = centralChallengeHash
    }

    public static func buildCargo(appInstanceId: Int, centralChallengeHash: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallengeHash
        )
    }
}

