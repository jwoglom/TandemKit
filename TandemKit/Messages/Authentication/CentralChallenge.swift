//
//  CentralChallenge.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of CentralChallengeRequest and CentralChallengeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/authentication/CentralChallengeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/CentralChallengeResponse.java
//

import Foundation

/// First message in the pump authorization handshake containing a random challenge.
public class CentralChallengeRequest: AbstractCentralChallengeRequest {
    public static var props = MessageProps(
        opCode: 16,
        size: 10,
        type: .Request,
        characteristic: .AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var centralChallenge: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.centralChallenge = cargo.subdata(in: 2..<10)
    }

    public init(appInstanceId: Int, centralChallenge: Data) {
        precondition(centralChallenge.count == 8)
        self.cargo = CentralChallengeRequest.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }

    public static func buildCargo(appInstanceId: Int, centralChallenge: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallenge
        )
    }
}

/// Response to `CentralChallengeRequest` providing challenge hash and HMAC key.
public class CentralChallengeResponse: AbstractCentralChallengeResponse {
    public static var props = MessageProps(
        opCode: 17,
        size: 30,
        type: .Response,
        characteristic: .AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var centralChallengeHash: Data
    public var hmacKey: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appInstanceId = Bytes.readShort(cargo, 0)
        self.centralChallengeHash = cargo.subdata(in: 2..<22)
        self.hmacKey = cargo.subdata(in: 22..<30)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data, hmacKey: Data) {
        precondition(centralChallengeHash.count == 20)
        precondition(hmacKey.count == 8)
        self.cargo = CentralChallengeResponse.buildCargo(appInstanceId: appInstanceId, centralChallengeHash: centralChallengeHash, hmacKey: hmacKey)
        self.appInstanceId = appInstanceId
        self.centralChallengeHash = centralChallengeHash
        self.hmacKey = hmacKey
    }

    public static func buildCargo(appInstanceId: Int, centralChallengeHash: Data, hmacKey: Data) -> Data {
        return Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallengeHash,
            hmacKey
        )
    }
}

