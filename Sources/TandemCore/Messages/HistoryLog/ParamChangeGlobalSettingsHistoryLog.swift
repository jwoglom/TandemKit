//
//  ParamChangeGlobalSettingsHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for global settings changes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ParamChangeGlobalSettingsHistoryLog.java
//
import Foundation

public class ParamChangeGlobalSettingsHistoryLog: HistoryLog {
    public static let typeId = 74

    public let modifiedData: Int
    public let qbDataStatus: Int
    public let qbActive: Int
    public let qbDataEntryType: Int
    public let qbIncrementUnits: Int
    public let qbIncrementCarbs: Int
    public let buttonVolume: Int
    public let qbVolume: Int
    public let bolusVolume: Int
    public let reminderVolume: Int
    public let alertVolume: Int

    public required init(cargo: Data) {
        self.modifiedData = Int(cargo[10])
        self.qbDataStatus = Int(cargo[11])
        self.qbActive = Int(cargo[12])
        self.qbDataEntryType = Int(cargo[13])
        self.qbIncrementUnits = Bytes.readShort(cargo, 14)
        self.qbIncrementCarbs = Bytes.readShort(cargo, 16)
        self.buttonVolume = Int(cargo[18])
        self.qbVolume = Int(cargo[19])
        self.bolusVolume = Int(cargo[20])
        self.reminderVolume = Int(cargo[21])
        self.alertVolume = Int(cargo[22])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, modifiedData: Int, qbDataStatus: Int, qbActive: Int, qbDataEntryType: Int, qbIncrementUnits: Int, qbIncrementCarbs: Int, buttonVolume: Int, qbVolume: Int, bolusVolume: Int, reminderVolume: Int, alertVolume: Int) {
        let payload = ParamChangeGlobalSettingsHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, modifiedData: modifiedData, qbDataStatus: qbDataStatus, qbActive: qbActive, qbDataEntryType: qbDataEntryType, qbIncrementUnits: qbIncrementUnits, qbIncrementCarbs: qbIncrementCarbs, buttonVolume: buttonVolume, qbVolume: qbVolume, bolusVolume: bolusVolume, reminderVolume: reminderVolume, alertVolume: alertVolume)
        self.modifiedData = modifiedData
        self.qbDataStatus = qbDataStatus
        self.qbActive = qbActive
        self.qbDataEntryType = qbDataEntryType
        self.qbIncrementUnits = qbIncrementUnits
        self.qbIncrementCarbs = qbIncrementCarbs
        self.buttonVolume = buttonVolume
        self.qbVolume = qbVolume
        self.bolusVolume = bolusVolume
        self.reminderVolume = reminderVolume
        self.alertVolume = alertVolume
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, modifiedData: Int, qbDataStatus: Int, qbActive: Int, qbDataEntryType: Int, qbIncrementUnits: Int, qbIncrementCarbs: Int, buttonVolume: Int, qbVolume: Int, bolusVolume: Int, reminderVolume: Int, alertVolume: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: modifiedData)]),
                Data([UInt8(truncatingIfNeeded: qbDataStatus)]),
                Data([UInt8(truncatingIfNeeded: qbActive)]),
                Data([UInt8(truncatingIfNeeded: qbDataEntryType)]),
                Bytes.firstTwoBytesLittleEndian(qbIncrementUnits),
                Bytes.firstTwoBytesLittleEndian(qbIncrementCarbs),
                Data([UInt8(truncatingIfNeeded: buttonVolume)]),
                Data([UInt8(truncatingIfNeeded: qbVolume)]),
                Data([UInt8(truncatingIfNeeded: bolusVolume)]),
                Data([UInt8(truncatingIfNeeded: reminderVolume)]),
                Data([UInt8(truncatingIfNeeded: alertVolume)])
            )
        )
    }
}

