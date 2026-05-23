import Foundation

/// Placeholder request for DetectingCartridgeStateStreamResponse which has no originating request.
public class NonexistentDetectingCartridgeStateStreamRequest: Message {
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

/// Stream message sent while the pump is detecting a new cartridge.
/// Supports both 2-byte (detecting cartridge progress) and 1-byte (load cartridge state) payloads.
public class DetectingCartridgeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-29)),
        size: 2,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        variableSize: true,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var percentComplete: Int
    public var stateId: Int
    public var loadCartridgeState: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        if cargo.count >= 2 {
            percentComplete = Bytes.readShort(cargo, 0)
            stateId = percentComplete
            loadCartridgeState = false
        } else {
            stateId = Int(cargo[0])
            percentComplete = stateId
            loadCartridgeState = true
        }
    }

    public init(percentComplete: Int) {
        cargo = Bytes.firstTwoBytesLittleEndian(percentComplete)
        self.percentComplete = percentComplete
        stateId = percentComplete
        loadCartridgeState = false
    }

    public var isComplete: Bool { percentComplete == 100 }

    public var description: String {
        "DetectingCartridgeStateStreamResponse(cargo=\(cargo.hexadecimalString), percentComplete=\(percentComplete), stateId=\(stateId), loadCartridgeState=\(loadCartridgeState))"
    }
}
