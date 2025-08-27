//
//  BasalIQAlertInfo.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of BasalIQAlertInfoRequest and BasalIQAlertInfoResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/BasalIQAlertInfoRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/BasalIQAlertInfoResponse.java
//

import Foundation

/// Request the most recent Basal-IQ alert info from the pump.
public class BasalIQAlertInfoRequest: Message {
    public static let props = MessageProps(
        opCode: 102,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response containing the Basal-IQ alert identifier.
public class BasalIQAlertInfoResponse: Message {
    public static let props = MessageProps(
        opCode: 103,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var alertId: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.alertId = Bytes.readUint32(cargo, 0)
    }

    public init(alertId: UInt32) {
        self.cargo = Bytes.toUint32(alertId)
        self.alertId = alertId
    }

    /// The enum alert associated with the alertId, if known.
    public var alert: BasalIQAlert? {
        return BasalIQAlert(rawValue: alertId)
    }

    /// Basal-IQ alert types.
    public enum BasalIQAlert: UInt32, CaseIterable {
        case NO_ALERT = 0
        case INSULIN_SUSPENDED_ALERT = 24576
        case INSULIN_RESUMED_ALERT = 24577
        case INSULIN_RESUMED_TIMEOUT = 24578
    }
}

