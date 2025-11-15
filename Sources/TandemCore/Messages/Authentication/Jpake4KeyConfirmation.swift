import Foundation

/// Final JPAKE message confirming key derivation.
public class Jpake4KeyConfirmationRequest: Message {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        nonce = cargo.subdata(in: 2 ..< 10)
        reserved = cargo.subdata(in: 10 ..< 18)
        hashDigest = cargo.subdata(in: 18 ..< 50)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        precondition(hashDigest.count == 32)
        cargo = Jpake4KeyConfirmationRequest.buildCargo(
            appInstanceId: appInstanceId,
            nonce: nonce,
            reserved: reserved,
            hashDigest: hashDigest
        )
        self.appInstanceId = appInstanceId
        self.nonce = nonce
        self.reserved = reserved
        self.hashDigest = hashDigest
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved,
            hashDigest
        )
    }
}

/// Response echoing the confirmation data from the pump.
public class Jpake4KeyConfirmationResponse: Message {
    public static let props = MessageProps(
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
        appInstanceId = Bytes.readShort(cargo, 0)
        nonce = cargo.subdata(in: 2 ..< 10)
        reserved = cargo.subdata(in: 10 ..< 18)
        hashDigest = cargo.subdata(in: 18 ..< 50)
    }

    public init(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) {
        precondition(nonce.count == 8)
        precondition(reserved.count == 8)
        precondition(hashDigest.count == 32)
        cargo = Jpake4KeyConfirmationResponse.buildCargo(
            appInstanceId: appInstanceId,
            nonce: nonce,
            reserved: reserved,
            hashDigest: hashDigest
        )
        self.appInstanceId = appInstanceId
        self.nonce = nonce
        self.reserved = reserved
        self.hashDigest = hashDigest
    }

    public static func buildCargo(appInstanceId: Int, nonce: Data, reserved: Data, hashDigest: Data) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(appInstanceId),
            nonce,
            reserved,
            hashDigest
        )
    }
}
