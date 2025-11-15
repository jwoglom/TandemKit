import Foundation

/// First half of the first JPAKE round containing a 165-byte challenge.
public class Jpake1aRequest: AbstractCentralChallengeRequest, CustomStringConvertible {
    public static let props = MessageProps(
        opCode: 32,
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallenge = cargo.subdata(in: 2 ..< 167)
    }

    public init(appInstanceId: Int, centralChallenge: Data) {
        self.appInstanceId = appInstanceId
        self.centralChallenge = Jpake1aRequest.normalizeChallenge(centralChallenge)
        cargo = Jpake1aRequest.buildCargo(appInstanceId: appInstanceId, centralChallenge: self.centralChallenge)
    }

    public static func buildCargo(appInstanceId: Int, centralChallenge: Data) -> Data {
        var cargo = Bytes.emptyBytes(167)
        let challenge = normalizeChallenge(centralChallenge)
        let combined = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            challenge
        )
        cargo.replaceSubrange(0 ..< 167, with: combined)
        return cargo
    }

    private static func normalizeChallenge(_ challenge: Data) -> Data {
        if challenge.count == 165 { return challenge }
        if challenge.count > 165 { return challenge.prefix(165) }
        var padded = Data(challenge)
        padded.append(Data(repeating: 0, count: 165 - challenge.count))
        return padded
    }

    public var description: String {
        let challengeHex = centralChallenge.map { String(format: "%02X", $0) }.joined()
        return "Jpake1aRequest(appInstanceId=\(appInstanceId), centralChallengeLength=\(centralChallenge.count), centralChallenge=\(challengeHex))"
    }
}

/// Response to `Jpake1aRequest` providing a 165-byte hash of the challenge.
public class Jpake1aResponse: AbstractCentralChallengeResponse {
    public static let props = MessageProps(
        opCode: 33,
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallengeHash = cargo.subdata(in: 2 ..< 167)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data) {
        precondition(centralChallengeHash.count == 165)
        cargo = Jpake1aResponse.buildCargo(appInstanceId: appInstanceId, centralChallengeHash: centralChallengeHash)
        self.appInstanceId = appInstanceId
        self.centralChallengeHash = centralChallengeHash
    }

    public static func buildCargo(appInstanceId: Int, centralChallengeHash: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallengeHash
        )
    }
}
