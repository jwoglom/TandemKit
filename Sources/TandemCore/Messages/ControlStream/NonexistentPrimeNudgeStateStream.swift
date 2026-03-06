import Foundation

/// Placeholder request for PrimeNudgeStateStreamResponse which has no originating request.
public class NonexistentPrimeNudgeStateStreamRequest: Message {
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

/// Stream message sent during prime nudge state.
/// Uses opcode -23 with a 1-byte stateId payload (same opcode as
/// ExitFillTubingModeStateStreamResponse and PumpingStateStreamResponse).
/// Identical wire format to ExitFillTubingModeStateStreamResponse but represents a different pump state.
public class PrimeNudgeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-23)),
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
        "PrimeNudgeStateStreamResponse(cargo=\(cargo.hexadecimalString), stateId=\(stateId))"
    }
}
