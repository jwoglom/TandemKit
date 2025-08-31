//
//  CgmDataGxHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's CgmDataGxHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmDataGxHistoryLog.java
//

import Foundation

/// History log entry containing a GX CGM data sample.
public class CgmDataGxHistoryLog: HistoryLog {
    public static let typeId = 211

    public let status: Int
    public let type: Int
    public let rate: Int
    public let rssi: Int
    public let value: Int
    public let timestamp: UInt32
    public let transmitterTimestamp: UInt32

    public required init(cargo: Data) {
        self.status = Bytes.readShort(cargo, 10)
        self.type = Int(cargo[12])
        self.rate = Int(cargo[13])
        self.rssi = Int(cargo[15])
        self.value = Bytes.readShort(cargo, 16)
        self.timestamp = Bytes.readUint32(cargo, 18)
        self.transmitterTimestamp = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, type: Int, rate: Int, rssi: Int, value: Int, timestamp: UInt32, transmitterTimestamp: UInt32) {
        let payload = CgmDataGxHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, status: status, type: type, rate: rate, rssi: rssi, value: value, timestamp: timestamp, transmitterTimestamp: transmitterTimestamp)
        self.status = status
        self.type = type
        self.rate = rate
        self.rssi = rssi
        self.value = value
        self.timestamp = timestamp
        self.transmitterTimestamp = transmitterTimestamp
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, type: Int, rate: Int, rssi: Int, value: Int, timestamp: UInt32, transmitterTimestamp: UInt32) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(status),
                Data([UInt8(type & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(value),
                Bytes.toUint32(timestamp),
                Bytes.toUint32(transmitterTimestamp)
            )
        )
    }
}

