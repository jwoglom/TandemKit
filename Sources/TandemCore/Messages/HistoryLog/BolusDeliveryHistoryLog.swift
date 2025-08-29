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
    public let reserved: Int
    public let requestedNow: Int
    public let requestedLater: Int
    public let correction: Int
    public let extendedDurationRequested: Int
    public let deliveredTotal: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        self.bolusID = Bytes.readShort(raw, 10)
        self.bolusDeliveryStatus = Int(raw[12])
        self.bolusTypeBitmask = Int(raw[13])
        self.bolusSource = Int(raw[14])
        self.reserved = Int(raw[15])
        self.requestedNow = Bytes.readShort(raw, 16)
        self.requestedLater = Bytes.readShort(raw, 18)
        self.correction = Bytes.readShort(raw, 20)
        self.extendedDurationRequested = Bytes.readShort(raw, 22)
        self.deliveredTotal = Bytes.readShort(raw, 24)
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusID: Int, bolusDeliveryStatus: Int, bolusTypeBitmask: Int, bolusSource: Int, reserved: Int, requestedNow: Int, requestedLater: Int, correction: Int, extendedDurationRequested: Int, deliveredTotal: Int) {
        let payload = BolusDeliveryHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bolusID: bolusID, bolusDeliveryStatus: bolusDeliveryStatus, bolusTypeBitmask: bolusTypeBitmask, bolusSource: bolusSource, reserved: reserved, requestedNow: requestedNow, requestedLater: requestedLater, correction: correction, extendedDurationRequested: extendedDurationRequested, deliveredTotal: deliveredTotal)
        self.bolusID = bolusID
        self.bolusDeliveryStatus = bolusDeliveryStatus
        self.bolusTypeBitmask = bolusTypeBitmask
        self.bolusSource = bolusSource
        self.reserved = reserved
        self.requestedNow = requestedNow
        self.requestedLater = requestedLater
        self.correction = correction
        self.extendedDurationRequested = extendedDurationRequested
        self.deliveredTotal = deliveredTotal
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusID: Int, bolusDeliveryStatus: Int, bolusTypeBitmask: Int, bolusSource: Int, reserved: Int, requestedNow: Int, requestedLater: Int, correction: Int, extendedDurationRequested: Int, deliveredTotal: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([24, 1]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusID),
                Data([UInt8(bolusDeliveryStatus & 0xFF)]),
                Data([UInt8(bolusTypeBitmask & 0xFF)]),
                Data([UInt8(bolusSource & 0xFF)]),
                Data([UInt8(reserved & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(requestedNow),
                Bytes.firstTwoBytesLittleEndian(requestedLater),
                Bytes.firstTwoBytesLittleEndian(correction),
                Bytes.firstTwoBytesLittleEndian(extendedDurationRequested),
                Bytes.firstTwoBytesLittleEndian(deliveredTotal)
            )
        )
    }

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

    public enum BolusType: Int, CaseIterable {
        case food1 = 1
        case correction = 2
        case extended = 4
        case food2 = 8

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
            return types.reduce(0) { $0 | $1.rawValue }
        }
    }
}

