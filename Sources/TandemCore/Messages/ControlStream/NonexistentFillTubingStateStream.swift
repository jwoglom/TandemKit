import Foundation

/// Placeholder request for FillTubingStateStreamResponse which has no originating request.
public class NonexistentFillTubingStateStreamRequest: Message {
    public static let props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Stream message received while tubing is being filled.
public class FillTubingStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-27)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var buttonState: Int

    public required init(cargo: Data) {
        let raw = Bytes.dropLastN(cargo, 0)
        self.cargo = raw
        buttonState = Int(raw[0])
    }

    public init(buttonState: Int) {
        cargo = Data([UInt8(buttonState & 0xFF)])
        self.buttonState = buttonState
    }

    public var buttonDown: Bool { buttonState == 1 }

    public var description: String {
        "FillTubingStateStreamResponse(cargo=\(cargo.hexadecimalString), buttonState=\(buttonState))"
    }
}
