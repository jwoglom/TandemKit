import Foundation

/// Request to send a TIPS control generic test command.
public class SendTipsControlGenericTestRequest: Message {
    public static let props = MessageProps(
        opCode: 118,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "SendTipsControlGenericTestRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response to a TIPS control generic test command.
public class SendTipsControlGenericTestResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: 119,
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }

    public enum StatusCode: Int {
        case ack = 0
        case invalidTestFeatureId = 1
        case invalidFeatureCommand = 2
        case unknown = 255
    }

    public var statusCode: StatusCode? { StatusCode(rawValue: status) }

    public var description: String {
        "SendTipsControlGenericTestResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
