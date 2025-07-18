//
//  PumpGlobals.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of PumpGlobalsRequest and PumpGlobalsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/PumpGlobalsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/PumpGlobalsResponse.java
//

import Foundation

/// Request global pump settings such as quick bolus configuration.
public class PumpGlobalsRequest: Message {
    public static var props = MessageProps(
        opCode: 86,
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

/// Response describing global pump settings.
public class PumpGlobalsResponse: Message {
    public static var props = MessageProps(
        opCode: 87,
        size: 14,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var quickBolusEnabledRaw: Int
    public var quickBolusIncrementUnits: Int
    public var quickBolusIncrementCarbs: Int
    public var quickBolusEntryType: Int
    public var quickBolusStatus: Int
    public var buttonAnnun: Int
    public var quickBolusAnnun: Int
    public var bolusAnnun: Int
    public var reminderAnnun: Int
    public var alertAnnun: Int
    public var alarmAnnun: Int
    public var fillTubingAnnun: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.quickBolusEnabledRaw = Int(cargo[0])
        self.quickBolusIncrementUnits = Bytes.readShort(cargo, 1)
        self.quickBolusIncrementCarbs = Bytes.readShort(cargo, 3)
        self.quickBolusEntryType = Int(cargo[5])
        self.quickBolusStatus = Int(cargo[6])
        self.buttonAnnun = Int(cargo[7])
        self.quickBolusAnnun = Int(cargo[8])
        self.bolusAnnun = Int(cargo[9])
        self.reminderAnnun = Int(cargo[10])
        self.alertAnnun = Int(cargo[11])
        self.alarmAnnun = Int(cargo[12])
        self.fillTubingAnnun = Int(cargo[13])
    }

    public init(quickBolusEnabledRaw: Int, quickBolusIncrementUnits: Int, quickBolusIncrementCarbs: Int, quickBolusEntryType: Int, quickBolusStatus: Int, buttonAnnun: Int, quickBolusAnnun: Int, bolusAnnun: Int, reminderAnnun: Int, alertAnnun: Int, alarmAnnun: Int, fillTubingAnnun: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(quickBolusEnabledRaw),
            Bytes.firstTwoBytesLittleEndian(quickBolusIncrementUnits),
            Bytes.firstTwoBytesLittleEndian(quickBolusIncrementCarbs),
            Bytes.firstByteLittleEndian(quickBolusEntryType),
            Bytes.firstByteLittleEndian(quickBolusStatus),
            Bytes.firstByteLittleEndian(buttonAnnun),
            Bytes.firstByteLittleEndian(quickBolusAnnun),
            Bytes.firstByteLittleEndian(bolusAnnun),
            Bytes.firstByteLittleEndian(reminderAnnun),
            Bytes.firstByteLittleEndian(alertAnnun),
            Bytes.firstByteLittleEndian(alarmAnnun),
            Bytes.firstByteLittleEndian(fillTubingAnnun)
        )
        self.quickBolusEnabledRaw = quickBolusEnabledRaw
        self.quickBolusIncrementUnits = quickBolusIncrementUnits
        self.quickBolusIncrementCarbs = quickBolusIncrementCarbs
        self.quickBolusEntryType = quickBolusEntryType
        self.quickBolusStatus = quickBolusStatus
        self.buttonAnnun = buttonAnnun
        self.quickBolusAnnun = quickBolusAnnun
        self.bolusAnnun = bolusAnnun
        self.reminderAnnun = reminderAnnun
        self.alertAnnun = alertAnnun
        self.alarmAnnun = alarmAnnun
        self.fillTubingAnnun = fillTubingAnnun
    }

    /// Convenience accessor to check if quick bolus is enabled.
    public func isQuickBolusEnabled() -> Bool {
        return quickBolusEnabledRaw == 1
    }

    /// Annunciation types for pump feedback.
    public enum AnnunciationEnum: Int {
        case audioHigh = 0
        case audioMedium = 1
        case audioLow = 2
        case vibrate = 3
    }
}

