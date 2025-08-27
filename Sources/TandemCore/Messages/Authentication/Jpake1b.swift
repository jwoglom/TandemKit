//
//  Jpake1b.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of Jpake1bRequest and Jpake1bResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/Jpake1bRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/Jpake1bResponse.java
//

import Foundation

/// Second half of the first JPAKE round.
public class Jpake1bRequest: Message {
    public static let props = MessageProps(
        opCode: 34,
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
        self.cargo = Jpake1bRequest.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
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

/// Response providing a hash of the second half of the first round.
public class Jpake1bResponse: Message {
    public static let props = MessageProps(
        opCode: 35,
        size: 167,
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
        self.centralChallengeHash = cargo.subdata(in: 2..<167)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data) {
        precondition(centralChallengeHash.count == 165)
        self.cargo = Jpake1bResponse.buildCargo(appInstanceId: appInstanceId, centralChallengeHash: centralChallengeHash)
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

