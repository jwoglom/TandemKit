//
//  BasalDeliveryHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's BasalDeliveryHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BasalDeliveryHistoryLog.java
//
import Foundation

/// History log entry detailing basal rate delivery.
public class BasalDeliveryHistoryLog: HistoryLog {
    public static let typeId = 279

    public let commandedRateSource: Int
    public let commandedRate: Int
    public let profileBasalRate: Int
    public let algorithmRate: Int
    public let tempRate: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        commandedRateSource = Bytes.readShort(raw, 10)
        commandedRate = Bytes.readShort(raw, 14)
        profileBasalRate = Bytes.readShort(raw, 16)
        algorithmRate = Bytes.readShort(raw, 18)
        tempRate = Bytes.readShort(raw, 20)
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        commandedRateSource: Int,
        commandedRate: Int,
        profileBasalRate: Int,
        algorithmRate: Int,
        tempRate: Int
    ) {
        let payload = BasalDeliveryHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            commandedRateSource: commandedRateSource,
            commandedRate: commandedRate,
            profileBasalRate: profileBasalRate,
            algorithmRate: algorithmRate,
            tempRate: tempRate
        )
        self.commandedRateSource = commandedRateSource
        self.commandedRate = commandedRate
        self.profileBasalRate = profileBasalRate
        self.algorithmRate = algorithmRate
        self.tempRate = tempRate
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        commandedRateSource: Int,
        commandedRate: Int,
        profileBasalRate: Int,
        algorithmRate: Int,
        tempRate: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([23, 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(commandedRateSource),
                Bytes.firstTwoBytesLittleEndian(commandedRate),
                Bytes.firstTwoBytesLittleEndian(profileBasalRate),
                Bytes.firstTwoBytesLittleEndian(algorithmRate),
                Bytes.firstTwoBytesLittleEndian(tempRate)
            )
        )
    }
}
