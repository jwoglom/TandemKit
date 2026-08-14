//
//  CurrentBatteryAbstractResponse.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's CurrentBatteryAbstractResponse.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CurrentBatteryAbstractResponse.java
//
import Foundation

/// Protocol defining common fields for current battery responses.
public protocol CurrentBatteryAbstractResponse: Message {
    /// Unused battery capacity percentage.
    var currentBatteryAbc: Int { get }
    /// Used battery capacity percentage displayed by the pump UI.
    var currentBatteryIbc: Int { get }
    /// Whether the pump is currently charging.
    var isCharging: Bool { get }
}

public extension CurrentBatteryAbstractResponse {
    /// Convenience accessor mapping to battery percent used by the pump UI.
    var batteryPercent: Int { currentBatteryIbc }

    /// Charging state is only carried by newer API versions. Responses without the field
    /// (such as `CurrentBatteryV1Response`) always report not charging.
    var isCharging: Bool { false }
}
