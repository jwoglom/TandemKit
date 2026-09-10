//
//  BolusDeliveryHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's BolusDeliveryHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusDeliveryHistoryLog.java
//
import Foundation

/// History log entry describing bolus delivery details.
public class BolusDeliveryHistoryLog: HistoryLog {
    public static let typeId = 280

    public let bolusID: Int
    public let bolusDeliveryStatus: Int
    public let bolusTypeBitmask: Int
    public let bolusSource: Int
    /// Byte 15. Named `remoteId` in Tandem's data export. In every record observed so far
    /// (312/312 in a Mobi capture and all earlier t:slim X2 fixtures) it equals
    /// `bolusID & 0xFF`, i.e. the low byte of the bolus id echoed back. Previously exposed as
    /// `reserved`. See pumpX2 issue #78.
    public let remoteId: Int
    public let requestedNow: Int
    public let requestedLater: Int
    public let correction: Int
    public let extendedDurationRequested: Int
    public let deliveredTotal: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        bolusID = Bytes.readShort(raw, 10)
        bolusDeliveryStatus = Int(raw[12])
        bolusTypeBitmask = Int(raw[13])
        bolusSource = Int(raw[14])
        remoteId = Int(raw[15])
        requestedNow = Bytes.readShort(raw, 16)
        requestedLater = Bytes.readShort(raw, 18)
        correction = Bytes.readShort(raw, 20)
        extendedDurationRequested = Bytes.readShort(raw, 22)
        deliveredTotal = Bytes.readShort(raw, 24)
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusID: Int,
        bolusDeliveryStatus: Int,
        bolusTypeBitmask: Int,
        bolusSource: Int,
        remoteId: Int,
        requestedNow: Int,
        requestedLater: Int,
        correction: Int,
        extendedDurationRequested: Int,
        deliveredTotal: Int
    ) {
        let payload = BolusDeliveryHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusID: bolusID,
            bolusDeliveryStatus: bolusDeliveryStatus,
            bolusTypeBitmask: bolusTypeBitmask,
            bolusSource: bolusSource,
            remoteId: remoteId,
            requestedNow: requestedNow,
            requestedLater: requestedLater,
            correction: correction,
            extendedDurationRequested: extendedDurationRequested,
            deliveredTotal: deliveredTotal
        )
        self.bolusID = bolusID
        self.bolusDeliveryStatus = bolusDeliveryStatus
        self.bolusTypeBitmask = bolusTypeBitmask
        self.bolusSource = bolusSource
        self.remoteId = remoteId
        self.requestedNow = requestedNow
        self.requestedLater = requestedLater
        self.correction = correction
        self.extendedDurationRequested = extendedDurationRequested
        self.deliveredTotal = deliveredTotal
        super.init(cargo: payload)
    }

    /// Source-compatibility overload for callers still using the `reserved:` label.
    @available(*, deprecated, renamed: "init(pumpTimeSec:sequenceNum:bolusID:bolusDeliveryStatus:bolusTypeBitmask:bolusSource:remoteId:requestedNow:requestedLater:correction:extendedDurationRequested:deliveredTotal:)")
    public convenience init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusID: Int,
        bolusDeliveryStatus: Int,
        bolusTypeBitmask: Int,
        bolusSource: Int,
        reserved: Int,
        requestedNow: Int,
        requestedLater: Int,
        correction: Int,
        extendedDurationRequested: Int,
        deliveredTotal: Int
    ) {
        self.init(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusID: bolusID,
            bolusDeliveryStatus: bolusDeliveryStatus,
            bolusTypeBitmask: bolusTypeBitmask,
            bolusSource: bolusSource,
            remoteId: reserved,
            requestedNow: requestedNow,
            requestedLater: requestedLater,
            correction: correction,
            extendedDurationRequested: extendedDurationRequested,
            deliveredTotal: deliveredTotal
        )
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusID: Int,
        bolusDeliveryStatus: Int,
        bolusTypeBitmask: Int,
        bolusSource: Int,
        remoteId: Int,
        requestedNow: Int,
        requestedLater: Int,
        correction: Int,
        extendedDurationRequested: Int,
        deliveredTotal: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusID),
                Data([UInt8(bolusDeliveryStatus & 0xFF)]),
                Data([UInt8(bolusTypeBitmask & 0xFF)]),
                Data([UInt8(bolusSource & 0xFF)]),
                Data([UInt8(remoteId & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(requestedNow),
                Bytes.firstTwoBytesLittleEndian(requestedLater),
                Bytes.firstTwoBytesLittleEndian(correction),
                Bytes.firstTwoBytesLittleEndian(extendedDurationRequested),
                Bytes.firstTwoBytesLittleEndian(deliveredTotal)
            )
        )
    }

    /// Source-compatibility overload for callers still using the `reserved:` label.
    @available(*, deprecated, renamed: "buildCargo(pumpTimeSec:sequenceNum:bolusID:bolusDeliveryStatus:bolusTypeBitmask:bolusSource:remoteId:requestedNow:requestedLater:correction:extendedDurationRequested:deliveredTotal:)")
    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusID: Int,
        bolusDeliveryStatus: Int,
        bolusTypeBitmask: Int,
        bolusSource: Int,
        reserved: Int,
        requestedNow: Int,
        requestedLater: Int,
        correction: Int,
        extendedDurationRequested: Int,
        deliveredTotal: Int
    ) -> Data {
        buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusID: bolusID,
            bolusDeliveryStatus: bolusDeliveryStatus,
            bolusTypeBitmask: bolusTypeBitmask,
            bolusSource: bolusSource,
            remoteId: reserved,
            requestedNow: requestedNow,
            requestedLater: requestedLater,
            correction: correction,
            extendedDurationRequested: extendedDurationRequested,
            deliveredTotal: deliveredTotal
        )
    }

    /// Former name of `remoteId`; byte 15 is not actually reserved.
    @available(*, deprecated, renamed: "remoteId")
    public var reserved: Int { remoteId }

    /// Set of bolus types associated with this record.
    public var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }

    /// Source that initiated the bolus.
    public var bolusSourceEnum: BolusSource? { BolusSource(rawValue: bolusSource) }

    public enum BolusSource: Int {
        case quickBolus = 0
        case gui = 1
        case controlIQAutoBolus = 7
        case bluetoothRemoteBolus = 8
    }

    /// Bitmask values validated against a real-pump capture (286/286 records cross-checked
    /// against per-bolus carb/correction/override data). Supersedes the previous
    /// {FOOD1=1, CORRECTION=2, EXTENDED=4, FOOD2=8} guess, which did not match observed data.
    public enum BolusType: Int, CaseIterable {
        case now = 1
        case later = 2
        case `override` = 4
        case correction = 8
        case carb = 16
        case eatingSoonMode = 32

        public static func fromBitmask(_ bitmask: Int) -> Set<BolusType> {
            var ret: Set<BolusType> = []
            for t in BolusType.allCases {
                if (bitmask & t.rawValue) != 0 {
                    ret.insert(t)
                }
            }
            return ret
        }

        public static func toBitmask(_ types: [BolusType]) -> Int {
            types.reduce(0) { $0 | $1.rawValue }
        }
    }

    public var description: String {
        "BolusDeliveryHistoryLog(cargo=\(cargo.hexadecimalString), bolusID=\(bolusID), bolusDeliveryStatus=\(bolusDeliveryStatus), bolusTypeBitmask=\(bolusTypeBitmask), bolusSourceEnum=\(String(describing: bolusSourceEnum)), bolusSource=\(bolusSource), remoteId=\(remoteId), requestedNow=\(requestedNow), requestedLater=\(requestedLater), correction=\(correction), extendedDurationRequested=\(extendedDurationRequested), deliveredTotal=\(deliveredTotal))"
    }
}
