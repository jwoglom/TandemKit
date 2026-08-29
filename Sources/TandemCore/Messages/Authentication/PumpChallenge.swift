import Foundation

/// Second authorization message carrying the HMACed pairing code.
public class PumpChallengeRequest: PumpRequest {
    public typealias Response = PumpChallengeResponse

    public static let props = MessageProps(
        opCode: 18,
        size: 22,
        type: .Request,
        characteristic: CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var pumpChallengeHash: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        appInstanceId = Bytes.readShort(cargo, 0)
        pumpChallengeHash = cargo.subdata(in: 2 ..< 22)
    }

    public init(appInstanceId: Int, pumpChallengeHash: Data) {
        precondition(pumpChallengeHash.count == 20)
        cargo = PumpChallengeRequest.buildCargo(appInstanceId: appInstanceId, pumpChallengeHash: pumpChallengeHash)
        self.appInstanceId = appInstanceId
        self.pumpChallengeHash = pumpChallengeHash
    }

    public static func buildCargo(appInstanceId: Int, pumpChallengeHash: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            pumpChallengeHash
        )
    }

    public var description: String {
        "PumpChallengeRequest(cargo=\(cargo.hexadecimalString), appInstanceId=\(appInstanceId), pumpChallengeHash=\(pumpChallengeHash.hexadecimalString))"
    }
}

/// Response indicating whether pairing succeeded.
public class PumpChallengeResponse: Message {
    public static let props = MessageProps(
        opCode: 19,
        size: 3,
        type: .Response,
        characteristic: CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS
    )

    public var cargo: Data
    public var appInstanceId: Int
    public var success: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        appInstanceId = Bytes.readShort(cargo, 0)
        success = cargo[2] == 1
    }

    public init(appInstanceId: Int, success: Bool) {
        cargo = PumpChallengeResponse.buildCargo(appInstanceId: appInstanceId, success: success)
        self.appInstanceId = appInstanceId
        self.success = success
    }

    public static func buildCargo(appInstanceId: Int, success: Bool) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            Data([UInt8(success ? 1 : 0)])
        )
    }

    public var description: String {
        "PumpChallengeResponse(cargo=\(cargo.hexadecimalString), appInstanceId=\(appInstanceId), success=\(success))"
    }
}
