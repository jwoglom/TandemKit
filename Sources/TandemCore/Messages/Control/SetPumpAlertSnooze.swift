//
//  SetPumpAlertSnooze.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetPumpAlertSnoozeRequest and SetPumpAlertSnoozeResponse based on
//  https://jwoglom.github.io/pumpX2/javadoc/messages/com/jwoglom/pumpx2/pump/messages/request/control/SetPumpAlertSnoozeRequest.html
//  https://jwoglom.github.io/pumpX2/javadoc/messages/com/jwoglom/pumpx2/pump/messages/response/control/SetPumpAlertSnoozeResponse.html
//

import Foundation

/// Request to enable or disable pump alert snooze timers.
public class SetPumpAlertSnoozeRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-44)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var snoozeEnabled: Bool
    public var snoozeDurationMins: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.snoozeEnabled = cargo[0] == 1
        self.snoozeDurationMins = Int(cargo[1])
    }

    public init(snoozeEnabled: Bool, snoozeDurationMins: Int) {
        self.cargo = SetPumpAlertSnoozeRequest.buildCargo(snoozeEnabled: snoozeEnabled, snoozeDurationMins: snoozeDurationMins)
        self.snoozeEnabled = snoozeEnabled
        self.snoozeDurationMins = snoozeDurationMins
    }

    public static func buildCargo(snoozeEnabled: Bool, snoozeDurationMins: Int) -> Data {
        return Data([
            UInt8(snoozeEnabled ? 1 : 0),
            UInt8(snoozeDurationMins & 0xFF)
        ])
    }
}

/// Response after setting the pump alert snooze preference.
public class SetPumpAlertSnoozeResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-43)),
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

