import Foundation

/// Placeholder request for FillCannulaStateStreamResponse which has no originating request.
public class NonexistentFillCannulaStateStreamRequest: Message {
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

/// Stream message sent while filling the cannula.
public class FillCannulaStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-25)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var stateId: Int

    public required init(cargo: Data) {
        let raw = Bytes.dropLastN(cargo, 0)
        self.cargo = raw
        stateId = Int(raw[0])
    }

    public init(stateId: Int) {
        cargo = Data([UInt8(stateId & 0xFF)])
        self.stateId = stateId
    }

    public var state: FillCannulaState? { FillCannulaState(rawValue: stateId) }

    public enum FillCannulaState: Int {
        case cannulaFilled = 2
    }

    public var description: String {
        "FillCannulaStateStreamResponse(cargo=\(cargo.hexadecimalString), state=\(String(describing: state)), stateId=\(stateId))"
    }
}
