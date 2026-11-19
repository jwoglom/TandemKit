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
    /// Minutes the extended part is programmed to run. In 30 extended boluses from Tandem's cloud export
    /// it equals BolusDelivery's `extendedDurationRequested`, and the run of each not stopped early.
    public let duration: Int
    public let spare1: Int
    public let isf: Int
    public let targetBG: Int
    public let userOverride: Bool
    public let declinedCorrection: Bool
    public let selectedIOB: Int
    public let spare2: Int

    /// Bolus request option, from the `options` byte at cargo offset 12.
    ///
    /// The case names come from tconnectsync's cloud mirror of this record and are otherwise
    /// unverified against the wire, with one exception: `bleStandard` (4) is confirmed on the
    /// wire. In a real-pump capture, 156/156 boluses initiated over BLE by a remote app
    /// (`InitiateBolusRequest`; `bolusSource` 8 in the paired `BolusDeliveryHistoryLog`) carried
    /// `options = 4` with `standardPercent` 100, `duration` 0, `userOverride` true, and
    /// `isf`/`targetBG` 0. The remaining cases were not exercised in that capture and remain
    /// unverified. See pumpX2 issue #51.
    public enum BolusOption: Int {
        case standard = 0
        case extended = 1
        case quick = 2
        case automatic = 3
        /// Standard (non-extended) bolus initiated over BLE by a remote app; verified on the wire.
        case bleStandard = 4
        case bleExtended = 5
        case eatingSoonAutomatic = 6
        case lateBolus = 7
        /// Tandem schema bit 8: BLE with AID Recommendation Bolus
        case bleWithAidRecommendation = 8
    }

    public enum SelectedIOBType: Int {
        case mudaliarIOB = 0
        case swanIOBMeal = 1
    }

    public var bolusOption: BolusOption? {
        BolusOption(rawValue: options)
    }

    public var selectedIOBType: SelectedIOBType? {
        SelectedIOBType(rawValue: selectedIOB)
    }

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
                HistoryLog.typeIdBytes(typeId),
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

    override public var description: String {
        "BolusRequestedMsg2HistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), options=\(options), standardPercent=\(standardPercent), duration=\(duration), spare1=\(spare1), isf=\(isf), targetBG=\(targetBG), userOverride=\(userOverride), declinedCorrection=\(declinedCorrection), selectedIOB=\(selectedIOB), spare2=\(spare2))"
    }
}
