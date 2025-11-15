import Foundation

/// Second JPAKE round message.
public class Jpake2Request: Message {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallenge = cargo.subdata(in: 2 ..< 167)
    }

    public init(appInstanceId: Int, centralChallenge: Data) {
        precondition(centralChallenge.count == 165)
        cargo = Jpake2Request.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }

    public static func buildCargo(appInstanceId: Int, centralChallenge: Data) -> Data {
        var cargo = Bytes.emptyBytes(167)
        let combined = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            centralChallenge
        )
        cargo.replaceSubrange(0 ..< 167, with: combined)
        return cargo
    }
}

/// Response to `Jpake2Request` with 168-byte hash.
public class Jpake2Response: Message {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        centralChallengeHash = cargo.subdata(in: 2 ..< 170)
    }

    public init(appInstanceId: Int, centralChallengeHash: Data) {
        precondition(centralChallengeHash.count == 168)
        cargo = Jpake2Response.buildCargo(appInstanceId: appInstanceId, centralChallengeHash: centralChallengeHash)
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
