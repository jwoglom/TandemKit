//
//  BolusRequestedMsg2HistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Second part of a multi-message bolus request log.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusRequestedMsg2HistoryLog.java
//
import Foundation

public class BolusRequestedMsg2HistoryLog: HistoryLog {
    public static let typeId = 65

    public let bolusId: Int
    public let options: Int
    public let standardPercent: Int
    public let duration: Int
    public let spare1: Int
    public let isf: Int
    public let targetBG: Int
    public let userOverride: Bool
    public let declinedCorrection: Bool
    public let selectedIOB: Int
    public let spare2: Int

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        options = Int(cargo[12])
        standardPercent = Int(cargo[13])
        duration = Bytes.readShort(cargo, 14)
        spare1 = Bytes.readShort(cargo, 16)
        isf = Bytes.readShort(cargo, 18)
        targetBG = Bytes.readShort(cargo, 20)
        userOverride = cargo[22] != 0
        declinedCorrection = cargo[23] != 0
        selectedIOB = Int(cargo[24])
        spare2 = Int(cargo.count > 25 ? cargo[25] : 0)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        options: Int,
        standardPercent: Int,
        duration: Int,
        spare1: Int,
        isf: Int,
        targetBG: Int,
        userOverride: Bool,
        declinedCorrection: Bool,
        selectedIOB: Int,
        spare2: Int
    ) {
        let payload = BolusRequestedMsg2HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            options: options,
            standardPercent: standardPercent,
            duration: duration,
            spare1: spare1,
            isf: isf,
            targetBG: targetBG,
            userOverride: userOverride,
            declinedCorrection: declinedCorrection,
            selectedIOB: selectedIOB,
            spare2: spare2
        )
        self.bolusId = bolusId
        self.options = options
        self.standardPercent = standardPercent
        self.duration = duration
        self.spare1 = spare1
        self.isf = isf
        self.targetBG = targetBG
        self.userOverride = userOverride
        self.declinedCorrection = declinedCorrection
        self.selectedIOB = selectedIOB
        self.spare2 = spare2
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        options: Int,
        standardPercent: Int,
        duration: Int,
        spare1: Int,
        isf: Int,
        targetBG: Int,
        userOverride: Bool,
        declinedCorrection: Bool,
        selectedIOB: Int,
        spare2: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([UInt8(options & 0xFF)]),
                Data([UInt8(standardPercent & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(duration),
                Bytes.firstTwoBytesLittleEndian(spare1),
                Bytes.firstTwoBytesLittleEndian(isf),
                Bytes.firstTwoBytesLittleEndian(targetBG),
                Data([userOverride ? 1 : 0]),
                Data([declinedCorrection ? 1 : 0]),
                Data([UInt8(selectedIOB & 0xFF)]),
                Data([UInt8(spare2 & 0xFF)])
            )
        )
    }
}
