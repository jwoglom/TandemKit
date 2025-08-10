//
//  NonexistentFillCannulaStateStream.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of NonexistentFillCannulaStateStreamRequest and FillCannulaStateStreamResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/controlStream/NonexistentFillCannulaStateStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/FillCannulaStateStreamResponse.java
//
import Foundation

/// Placeholder request for FillCannulaStateStreamResponse which has no originating request.
public class NonexistentFillCannulaStateStreamRequest: Message {
    public static var props = MessageProps(
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

/// Stream message sent while filling the cannula.
public class FillCannulaStateStreamResponse: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-25)),
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

    public var state: FillCannulaState? { FillCannulaState(rawValue: stateId) }

    public enum FillCannulaState: Int {
        case cannulaFilled = 2
    }
}

