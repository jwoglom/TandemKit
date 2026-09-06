import Foundation

/// Placeholder request for PumpingStateStreamResponse which has no originating request.
public class NonexistentPumpingStateStreamRequest: Message {
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

/// Stream response containing pump state bitmask information.
public class PumpingStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-23)),
        size: 5,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var isPumpingStateSetAfterStartUp: Bool
    public var stateBitmask: UInt32

    public required init(cargo: Data) {
        // Shares the trailer-stripping rule with ExitFillTubingModeStateStreamResponse: the two
        // are the same wire message under opcode -23, told apart only by payload size.
        let raw = ExitFillTubingModeStateStreamResponse.payload(from: cargo)
        self.cargo = raw
        isPumpingStateSetAfterStartUp = raw.count >= 5 && raw[0] != 0
        stateBitmask = raw.count >= 5 ? Bytes.readUint32(raw, 1) : 0
    }

    public init(isPumpingStateSetAfterStartUp: Bool, stateBitmask: UInt32) {
        cargo = Bytes.combine(
            Data([isPumpingStateSetAfterStartUp ? 1 : 0]),
            Bytes.toUint32(stateBitmask)
        )
        self.isPumpingStateSetAfterStartUp = isPumpingStateSetAfterStartUp
        self.stateBitmask = stateBitmask
    }

    public var states: Set<PumpingState> {
        var result: Set<PumpingState> = []
        for state in PumpingState.allCases {
            if (stateBitmask & state.rawValue) != 0 {
                result.insert(state)
            }
        }
        return result
    }

    public enum PumpingState: UInt32, CaseIterable {
        case isDeliveringTherapy = 1
        case canResumeTherapy = 2
        case canAutoResume = 4
        case bolusAllowed = 8
        case tubingFilled = 16
        case deliveringBasal = 32
        case deliveringBolus = 64
        case deliveringNormalBolus = 128
        case isFillTubingAllowed = 256
        case isBasalState = 512
        case isPrepCartridgeState = 1024
        case isLoadCartridgeState = 2048
        case isFillState = 4096
        case isEstimateState = 8192
        case cartridgeIsInstalled = 16384
        case canSnooze = 32768
    }

    public var description: String {
        "PumpingStateStreamResponse(cargo=\(cargo.hexadecimalString), isPumpingStateSetAfterStartUp=\(isPumpingStateSetAfterStartUp), stateBitmask=\(stateBitmask))"
    }
}
