import Foundation

/// Placeholder request for LoadCartridgeStateStreamResponse which has no originating request.
public class NonexistentLoadCartridgeStateStreamRequest: Message {
    public static let props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Request,
        characteristic: .CONTROL_STREAM_CHARACTERISTICS,
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

/// Stream message sent while the pump is loading a new cartridge.
/// Uses opcode -29 with a 1-byte stateId payload, distinguished from
/// DetectingCartridgeStateStreamResponse (2-byte percentComplete) by payload length.
public class LoadCartridgeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-29)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var stateId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        stateId = Int(cargo[0])
    }

    public init(stateId: Int) {
        cargo = Data([UInt8(stateId & 0xFF)])
        self.stateId = stateId
    }

    public var description: String {
        "LoadCartridgeStateStreamResponse(cargo=\(cargo.hexadecimalString), stateId=\(stateId))"
    }
}
