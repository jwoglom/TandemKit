import Foundation

/// First message in the pump authorization handshake containing a random challenge.
public class CentralChallengeRequest: AbstractCentralChallengeRequest {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallenge = cargo.subdata(in: 2 ..< 10)
    }

    public init(appInstanceId: Int, centralChallenge: Data) {
        precondition(centralChallenge.count == 8)
        cargo = CentralChallengeRequest.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }

    public static func buildCargo(appInstanceId: Int, centralChallenge: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallenge
        )
    }
}

/// Response to `CentralChallengeRequest` providing challenge hash and HMAC key.
public class CentralChallengeResponse: AbstractCentralChallengeResponse {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallengeHash = cargo.subdata(in: 2 ..< 22)
        hmacKey = cargo.subdata(in: 22 ..< 30)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data, hmacKey: Data) {
        precondition(centralChallengeHash.count == 20)
        precondition(hmacKey.count == 8)
        cargo = CentralChallengeResponse.buildCargo(
            appInstanceId: appInstanceId,
            centralChallengeHash: centralChallengeHash,
            hmacKey: hmacKey
        )
        self.appInstanceId = appInstanceId
        self.centralChallengeHash = centralChallengeHash
        self.hmacKey = hmacKey
    }

    public static func buildCargo(appInstanceId: Int, centralChallengeHash: Data, hmacKey: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallengeHash,
            hmacKey
        )
    }
}
