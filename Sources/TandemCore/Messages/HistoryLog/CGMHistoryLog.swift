//
//  CGMHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry containing CGM data.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CGMHistoryLog.java
//
import Foundation

public class CGMHistoryLog: HistoryLog {
    public static let typeId = 256

    public let glucoseValueStatus: Int
    public let cgmDataType: Int
    public let rate: Int
    public let algorithmState: Int
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let timeStampSeconds: UInt32
    public let egvInfoBitmask: Int
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatus = Bytes.readShort(cargo, 10)
        cgmDataType = Int(cargo[12])
        rate = Int(cargo[13])
        algorithmState = Int(cargo[14])
        rssi = Int(cargo[15])
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        timeStampSeconds = Bytes.readUint32(cargo, 18)
        egvInfoBitmask = Bytes.readShort(cargo, 22)
        interval = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatus: Int,
        cgmDataType: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmask: Int,
        interval: Int
    ) {
        let payload = CGMHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            glucoseValueStatus: glucoseValueStatus,
            cgmDataType: cgmDataType,
            rate: rate,
            algorithmState: algorithmState,
            rssi: rssi,
            currentGlucoseDisplayValue: currentGlucoseDisplayValue,
            timeStampSeconds: timeStampSeconds,
            egvInfoBitmask: egvInfoBitmask,
            interval: interval
        )
        self.glucoseValueStatus = glucoseValueStatus
        self.cgmDataType = cgmDataType
        self.rate = rate
        self.algorithmState = algorithmState
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.timeStampSeconds = timeStampSeconds
        self.egvInfoBitmask = egvInfoBitmask
        self.interval = interval
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatus: Int,
        cgmDataType: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmask: Int,
        interval: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([0, 1]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(glucoseValueStatus),
                Data([UInt8(cgmDataType & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([UInt8(algorithmState & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(timeStampSeconds),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmask),
                Data([UInt8(interval & 0xFF)]),
                Data([1]) // trailing param as in Java implementation
            )
        )
    }
}
