import Foundation

/// Placeholder request for ExitFillTubingModeStateStreamResponse which has no originating request.
public class NonexistentExitFillTubingModeStateStreamRequest: Message {
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

/// Stream message sent while the pump exits fill tubing mode.
/// Supports both 1-byte (exit-fill-tubing / prime-nudge state) and 5-byte (pumping state) payloads.
public class ExitFillTubingModeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-23)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS,
        variableSize: true,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var stateId: Int
    public var isPumpingStateSetAfterStartUp: Bool
    public var stateBitmask: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        stateId = Int(cargo[0] & 0xFF)
        if cargo.count >= 5 {
            isPumpingStateSetAfterStartUp = cargo[0] != 0
            stateBitmask = Bytes.readUint32(cargo, 1)
        } else {
            isPumpingStateSetAfterStartUp = false
            stateBitmask = 0
        }
    }

    public init(stateId: Int) {
        cargo = Data([UInt8(stateId & 0xFF)])
        self.stateId = stateId
        isPumpingStateSetAfterStartUp = false
        stateBitmask = 0
    }

    public init(isPumpingStateSetAfterStartUp: Bool, stateBitmask: UInt32) {
        cargo = Bytes.combine(
            Data([isPumpingStateSetAfterStartUp ? 1 : 0]),
            Bytes.toUint32(stateBitmask)
        )
        stateId = Int(cargo[0] & 0xFF)
        self.isPumpingStateSetAfterStartUp = isPumpingStateSetAfterStartUp
        self.stateBitmask = stateBitmask
    }

    public var state: ExitFillTubingModeState? { ExitFillTubingModeState(rawValue: stateId) }

    public var pumpingStates: Set<PumpingState> { PumpingState.fromBitmask(stateBitmask) }

    public enum ExitFillTubingModeState: Int {
        case notComplete = 0
        case tubingFilled = 1
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

        public static func fromBitmask(_ bitmask: UInt32) -> Set<PumpingState> {
            var result = Set<PumpingState>()
            for s in PumpingState.allCases {
                if (bitmask & s.rawValue) != 0 {
                    result.insert(s)
                }
            }
            return result
        }

        public static func toBitmask(_ states: [PumpingState]) -> UInt32 {
            var bitmask: UInt32 = 0
            for s in states {
                bitmask |= s.rawValue
            }
            return bitmask
        }
    }

    public var description: String {
        "ExitFillTubingModeStateStreamResponse(cargo=\(cargo.hexadecimalString), state=\(String(describing: state)), stateId=\(stateId), isPumpingStateSetAfterStartUp=\(isPumpingStateSetAfterStartUp), stateBitmask=\(stateBitmask))"
    }
}
