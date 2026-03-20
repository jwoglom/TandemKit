import Foundation

/// Request to signal user interaction with the pump.
public class UserInteractionRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-124)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
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
        "UserInteractionRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response to a user interaction request.
public class UserInteractionResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-123)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
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

    public var description: String {
        "UserInteractionResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
