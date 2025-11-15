import Foundation

/// Request the saved Dexcom G7 pairing code.
public class GetSavedG7PairingCodeRequest: Message {
    public static let props = MessageProps(
        opCode: 116,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response with the saved Dexcom G7 pairing code.
public class GetSavedG7PairingCodeResponse: Message {
    public static let props = MessageProps(
        opCode: 117,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var pairingCode: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        pairingCode = Bytes.readShort(cargo, 0)
    }

    public init(pairingCode: Int) {
        cargo = Bytes.firstTwoBytesLittleEndian(pairingCode)
        self.pairingCode = pairingCode
    }
}
