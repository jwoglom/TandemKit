import Foundation

/// Request miscellaneous notification status (Mobi only).
public class OtherNotificationStatusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-110)),
        size: 1,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data([0])
    }

    public var description: String {
        "OtherNotificationStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response for miscellaneous notifications (Mobi only).
public class OtherNotificationStatusResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-109)),
        size: 17,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Bytes.emptyBytes(Int(Self.props.size))
    }

    public var description: String {
        "OtherNotificationStatusResponse(cargo=\(cargo.hexadecimalString))"
    }
}
