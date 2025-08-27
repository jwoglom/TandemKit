//
//  NonexistentDetectingCartridgeStateStream.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of NonexistentDetectingCartridgeStateStreamRequest and DetectingCartridgeStateStreamResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/controlStream/NonexistentDetectingCartridgeStateStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/DetectingCartridgeStateStreamResponse.java
//
import Foundation

/// Placeholder request for DetectingCartridgeStateStreamResponse which has no originating request.
public class NonexistentDetectingCartridgeStateStreamRequest: Message {
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

/// Stream message sent while the pump is detecting a new cartridge.
public class DetectingCartridgeStateStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-29)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_STREAM_CHARACTERISTICS,
        stream: true,
        signed: true
    )

    public var cargo: Data
    public var percentComplete: Int

    public required init(cargo: Data) {
        let raw = Bytes.dropLastN(cargo, 0)
        self.cargo = raw
        self.percentComplete = Bytes.readShort(raw, 0)
    }

    public init(percentComplete: Int) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(percentComplete)
        self.percentComplete = percentComplete
    }

    public var isComplete: Bool { percentComplete == 100 }
}

