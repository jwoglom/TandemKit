//
//  NonexistentEnterChangeCartridgeModeStateStream.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of NonexistentEnterChangeCartridgeModeStateStreamRequest and EnterChangeCartridgeModeStateStreamResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/controlStream/NonexistentEnterChangeCartridgeModeStateStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/EnterChangeCartridgeModeStateStreamResponse.java
//
import Foundation

/// Placeholder request for EnterChangeCartridgeModeStateStreamResponse which has no originating request.
public class NonexistentEnterChangeCartridgeModeStateStreamRequest: Message {
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

/// Stream message emitted during the change cartridge process.
public class EnterChangeCartridgeModeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-31)),
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
        self.stateId = Int(raw[0])
    }

    public init(stateId: Int) {
        self.cargo = Data([UInt8(stateId & 0xFF)])
        self.stateId = stateId
    }

    public var state: ChangeCartridgeState? { ChangeCartridgeState(rawValue: stateId) }

    public enum ChangeCartridgeState: Int {
        case readyToChange = 2
    }
}

