//
//  NonexistentPumpingStateStream.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of NonexistentPumpingStateStreamRequest and PumpingStateStreamResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/controlStream/NonexistentPumpingStateStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/PumpingStateStreamResponse.java
//
import Foundation

/// Placeholder request for PumpingStateStreamResponse which has no originating request.
public class NonexistentPumpingStateStreamRequest: Message {
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
        self.cargo = Data()
    }
}

/// Stream response containing pump state bitmask information.
public class PumpingStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-23)),
        size: 5,
        type: .Response,
        characteristic: .CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var isPumpingStateSetAfterStartUp: Bool
    public var stateBitmask: UInt32

    public required init(cargo: Data) {
        let raw = Bytes.dropLastN(cargo, 24)
        self.cargo = raw
        self.isPumpingStateSetAfterStartUp = raw[0] != 0
        self.stateBitmask = Bytes.readUint32(raw, 1)
    }

    public init(isPumpingStateSetAfterStartUp: Bool, stateBitmask: UInt32) {
        self.cargo = Bytes.combine(
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
}

