//
//  PumpChallenge.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of PumpChallengeRequest and PumpChallengeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/PumpChallengeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/PumpChallengeResponse.java
//

import Foundation

/// Second authorization message carrying the HMACed pairing code.
public class PumpChallengeRequest: Message {
    public static var props = MessageProps(
        opCode: 18,
        size: 22,
        type: .Request,
        characteristic: .AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var pumpChallengeHash: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.pumpChallengeHash = cargo.subdata(in: 2..<22)
    }

    public init(appInstanceId: Int, pumpChallengeHash: Data) {
        precondition(pumpChallengeHash.count == 20)
        self.cargo = PumpChallengeRequest.buildCargo(appInstanceId: appInstanceId, pumpChallengeHash: pumpChallengeHash)
        self.appInstanceId = appInstanceId
        self.pumpChallengeHash = pumpChallengeHash
    }

    public static func buildCargo(appInstanceId: Int, pumpChallengeHash: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            pumpChallengeHash
        )
    }
}

/// Response indicating whether pairing succeeded.
public class PumpChallengeResponse: Message {
    public static var props = MessageProps(
        opCode: 19,
        size: 3,
        type: .Response,
        characteristic: .AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var success: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.success = cargo[2] == 1
    }

    public init(appInstanceId: Int, success: Bool) {
        self.cargo = PumpChallengeResponse.buildCargo(appInstanceId: appInstanceId, success: success)
        self.appInstanceId = appInstanceId
        self.success = success
    }

    public static func buildCargo(appInstanceId: Int, success: Bool) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            Data([UInt8(success ? 1 : 0)])
        )
    }
}

