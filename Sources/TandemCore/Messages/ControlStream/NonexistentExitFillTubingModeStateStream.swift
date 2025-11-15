//
//  NonexistentExitFillTubingModeStateStream.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of NonexistentExitFillTubingModeStateStreamRequest and ExitFillTubingModeStateStreamResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/controlStream/NonexistentExitFillTubingModeStateStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/ExitFillTubingModeStateStreamResponse.java
//
import Foundation

/// Placeholder request for ExitFillTubingModeStateStreamResponse which has no originating request.
public class NonexistentExitFillTubingModeStateStreamRequest: Message {
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

/// Stream message sent while the pump exits fill tubing mode.
public class ExitFillTubingModeStateStreamResponse: Message {
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
        let raw = Bytes.dropLastN(cargo, 0)
        self.cargo = raw
        stateId = Int(raw[0])
    }

    public init(stateId: Int) {
        cargo = Data([UInt8(stateId & 0xFF)])
        self.stateId = stateId
    }

    public var state: ExitFillTubingModeState? { ExitFillTubingModeState(rawValue: stateId) }

    public enum ExitFillTubingModeState: Int {
        case notComplete = 0
        case tubingFilled = 1
    }
}
