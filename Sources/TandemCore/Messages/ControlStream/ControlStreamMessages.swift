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
    /// Determines which request message corresponds to a control stream response payload.
    /// - Parameter rawBtValue: Raw Bluetooth payload including the opcode at index 2.
    /// - Returns: A new instance of the associated request message, or `nil` if unknown.
    public static func determineRequestMessage(rawBtValue: Data) -> Message? {
        precondition(rawBtValue.count >= 3)
        let opCode = rawBtValue[2]
        switch opCode {
        case DetectingCartridgeStateStreamResponse.props.opCode:
            return NonexistentDetectingCartridgeStateStreamRequest()
        case EnterChangeCartridgeModeStateStreamResponse.props.opCode:
            return NonexistentEnterChangeCartridgeModeStateStreamRequest()
        case FillTubingStateStreamResponse.props.opCode:
            return NonexistentFillTubingStateStreamRequest()
        case FillCannulaStateStreamResponse.props.opCode:
            return NonexistentFillCannulaStateStreamRequest()
        case UInt8(bitPattern: Int8(-23)):
            // Both ExitFillTubingModeStateStreamResponse and PumpingStateStreamResponse use this opcode.
            // Distinguish by payload length: PumpingStateStreamResponse has additional padding bytes.
            if rawBtValue.count >= 29 {
                return NonexistentPumpingStateStreamRequest()
            } else {
                return NonexistentExitFillTubingModeStateStreamRequest()
            }
        default:
            return nil
        }
    }
}

