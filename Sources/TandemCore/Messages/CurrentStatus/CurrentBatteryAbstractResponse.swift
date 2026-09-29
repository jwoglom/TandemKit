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
    /// A second 0-100 charge figure, not the displayed one; DailyBasal history logs this one on Mobi (jwoglom/pumpX2#149).
    var currentBatteryAbc: Int { get }
    /// Charge remaining, 0-100, as the pump displays it.
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
