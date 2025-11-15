import Foundation

/// Third JPAKE message triggering session key validation.
public class Jpake3SessionKeyRequest: Message {
    public static let props = MessageProps(
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
        challengeParam = Bytes.readShort(cargo, 0)
    }

    public init(challengeParam: Int) {
        cargo = Jpake3SessionKeyRequest.buildCargo(challengeParam: challengeParam)
        self.challengeParam = challengeParam
    }

    public static func buildCargo(challengeParam: Int) -> Data {
        Bytes.firstTwoBytesLittleEndian(challengeParam)
    }
}

/// Response with nonce and reserved values.
public class Jpake3SessionKeyResponse: Message {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        deviceKeyNonce = cargo.subdata(in: 2 ..< 10)
        deviceKeyReserved = cargo.subdata(in: 10 ..< 18)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        cargo = Jpake3SessionKeyResponse.buildCargo(appInstanceId: appInstanceId, nonce: nonce, reserved: reserved)
        self.appInstanceId = appInstanceId
        deviceKeyNonce = nonce
        deviceKeyReserved = reserved
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved
        )
    }
}
