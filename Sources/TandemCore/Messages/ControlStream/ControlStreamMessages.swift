//
//  ControlStreamMessages.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's ControlStreamMessages.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/controlStream/ControlStreamMessages.java
//
import Foundation

/// Utility for determining the paired request message for a control stream response.
public enum ControlStreamMessages {
    /// The control stream response with `opCode` whose header declares `payloadLength`. Two pairs
    /// share an opcode and differ only in size: DetectingCartridgeStateStreamResponse (2 bytes) and
    /// LoadCartridgeStateStreamResponse (1) under -29, PumpingStateStreamResponse (5) and
    /// ExitFillTubingModeStateStreamResponse (1) under -23. Each size is accepted signed, with the
    /// 24-byte trailer, or not, as pumpX2's PacketArrayList accepts them.
    public static func responseType(opCode: UInt8, payloadLength: Int) -> Message.Type? {
        func hasSize(of type: Message.Type) -> Bool {
            let size = Int(type.props.size)
            return payloadLength == size || payloadLength == size + 24
        }

        switch opCode {
        case DetectingCartridgeStateStreamResponse.props.opCode:
            return hasSize(of: DetectingCartridgeStateStreamResponse.self)
                ? DetectingCartridgeStateStreamResponse.self
                : LoadCartridgeStateStreamResponse.self
        case EnterChangeCartridgeModeStateStreamResponse.props.opCode:
            return EnterChangeCartridgeModeStateStreamResponse.self
        case FillTubingStateStreamResponse.props.opCode:
            return FillTubingStateStreamResponse.self
        case FillCannulaStateStreamResponse.props.opCode:
            return FillCannulaStateStreamResponse.self
        case PumpingStateStreamResponse.props.opCode:
            return hasSize(of: PumpingStateStreamResponse.self)
                ? PumpingStateStreamResponse.self
                : ExitFillTubingModeStateStreamResponse.self
        default:
            return nil
        }
    }

    /// Determines which request message corresponds to a control stream response payload.
    /// - Parameter rawBtValue: Raw Bluetooth payload including the opcode at index 2 and the
    ///   payload length at index 4.
    /// - Returns: A new instance of the associated request message, or `nil` if unknown.
    public static func determineRequestMessage(rawBtValue: Data) -> Message? {
        precondition(rawBtValue.count >= 3)
        let raw = Data(rawBtValue)
        let payloadLength = raw.count > 4 ? Int(raw[4]) : 0
        switch responseType(opCode: raw[2], payloadLength: payloadLength) {
        case let type? where type == DetectingCartridgeStateStreamResponse.self:
            return NonexistentDetectingCartridgeStateStreamRequest()
        case let type? where type == LoadCartridgeStateStreamResponse.self:
            return NonexistentLoadCartridgeStateStreamRequest()
        case let type? where type == EnterChangeCartridgeModeStateStreamResponse.self:
            return NonexistentEnterChangeCartridgeModeStateStreamRequest()
        case let type? where type == FillTubingStateStreamResponse.self:
            return NonexistentFillTubingStateStreamRequest()
        case let type? where type == FillCannulaStateStreamResponse.self:
            return NonexistentFillCannulaStateStreamRequest()
        case let type? where type == PumpingStateStreamResponse.self:
            return NonexistentPumpingStateStreamRequest()
        case let type? where type == ExitFillTubingModeStateStreamResponse.self:
            return NonexistentExitFillTubingModeStateStreamRequest()
        default:
            return nil
        }
    }
}
