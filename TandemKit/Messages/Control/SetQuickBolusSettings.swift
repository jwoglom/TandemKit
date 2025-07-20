//
//  SetQuickBolusSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetQuickBolusSettingsRequest and SetQuickBolusSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetQuickBolusSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetQuickBolusSettingsResponse.java
//

import Foundation

/// Request to configure quick bolus button behavior.
public class SetQuickBolusSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-46)),
        size: 7,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enabled: Bool
    public var modeRaw: Int
    public var magic: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.enabled = cargo[0] == 1
        self.modeRaw = Int(cargo[1])
        self.magic = Bytes.dropFirstN(cargo, 2)
    }

    public init(enabled: Bool, modeRaw: Int, magic: Data) {
        self.cargo = Bytes.combine(
            Data([UInt8(enabled ? 1 : 0)]),
            Data([UInt8(modeRaw & 0xFF)]),
            magic
        )
        self.enabled = enabled
        self.modeRaw = modeRaw
        self.magic = magic
    }

    public convenience init(enabled: Bool, mode: QuickBolusMode, increment: QuickBolusIncrement) {
        self.init(enabled: enabled, modeRaw: mode.rawValue, magic: increment.magic)
    }

    public var mode: QuickBolusMode? { QuickBolusMode(rawValue: modeRaw) }
    public var increment: QuickBolusIncrement? { QuickBolusIncrement.forMagic(magic) }
}

/// Supported quick bolus modes.
public enum QuickBolusMode: Int {
    case units = 0
    case carbs = 1
}

/// Predefined quick bolus increments.
public enum QuickBolusIncrement: CaseIterable {
    case disabled
    case units0_5
    case units1_0
    case units2_0
    case units5_0
    case carbs2g
    case carbs5g
    case carbs10g
    case carbs15g

    var enabled: Bool {
        switch self {
        case .disabled: return false
        default: return true
        }
    }

    var mode: QuickBolusMode {
        switch self {
        case .carbs2g, .carbs5g, .carbs10g, .carbs15g: return .carbs
        default: return .units
        }
    }

    var magic: Data {
        switch self {
        case .disabled: return Data([0xF4,0x01,0xD0,0x07,0x01])
        case .units0_5: return Data([0xF4,0x01,0xD0,0x07,0x01])
        case .units1_0: return Data([0xE8,0x03,0xD0,0x07,0x04])
        case .units2_0: return Data([0xD0,0x07,0xD0,0x07,0x04])
        case .units5_0: return Data([0x88,0x13,0xD0,0x07,0x04])
        case .carbs2g: return Data([0x88,0x13,0xD0,0x07,0x08])
        case .carbs5g: return Data([0x88,0x13,0x88,0x13,0x08])
        case .carbs10g: return Data([0x88,0x13,0x10,0x27,0x08])
        case .carbs15g: return Data([0x88,0x13,0x98,0x3A,0x08])
        }
    }

    static func forMagic(_ magic: Data) -> QuickBolusIncrement? {
        for inc in QuickBolusIncrement.allCases where inc.enabled && inc.magic == magic {
            return inc
        }
        return nil
    }
}

/// Response indicating if quick bolus settings were updated.
public class SetQuickBolusSettingsResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-45)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
    }

    public init(status: Int) {
        self.cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}

