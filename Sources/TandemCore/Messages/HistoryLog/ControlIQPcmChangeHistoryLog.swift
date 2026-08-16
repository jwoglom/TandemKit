//
//  ControlIQPcmChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's ControlIQPcmChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ControlIQPcmChangeHistoryLog.java
//
import Foundation

/// History log entry indicating a ControlIQ Pump Control Mode (PCM) change.
public class ControlIQPcmChangeHistoryLog: HistoryLog {
    public static let typeId = 230

    public let currentPcm: Int
    public let previousPcm: Int
    public let pumpSuspendedRaw: Int
    public let calculationAvailableRaw: Int
    public let cgmAvailableRaw: Int
    public let closedLoopPreferredRaw: Int
    public let sufficientClosedLoopParamsRaw: Int

    public enum PCM: Int {
        case noControl = 0
        case openLoop = 1
        case cgmInactive = 2
        case closedLoop = 3
    }

    public var currentPcmEnum: PCM? {
        PCM(rawValue: currentPcm)
    }

    public var previousPcmEnum: PCM? {
        PCM(rawValue: previousPcm)
    }

    public var isPumpSuspended: Bool {
        pumpSuspendedRaw != 0
    }

    public var isCalculationAvailable: Bool {
        calculationAvailableRaw != 0
    }

    public var isCgmAvailable: Bool {
        cgmAvailableRaw != 0
    }

    public var isClosedLoopPreferred: Bool {
        closedLoopPreferredRaw != 0
    }

    public var isSufficientClosedLoopParams: Bool {
        sufficientClosedLoopParamsRaw != 0
    }

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        currentPcm = Int(raw[10])
        previousPcm = Int(raw[11])
        pumpSuspendedRaw = Int(raw[12])
        calculationAvailableRaw = Int(raw[13])
        cgmAvailableRaw = Int(raw[14])
        closedLoopPreferredRaw = Int(raw[15])
        sufficientClosedLoopParamsRaw = Int(raw[16])
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentPcm: Int,
        previousPcm: Int,
        pumpSuspended: Int,
        calculationAvailable: Int,
        cgmAvailable: Int,
        closedLoopPreferred: Int,
        sufficientClosedLoopParams: Int
    ) {
        let payload = ControlIQPcmChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentPcm: currentPcm,
            previousPcm: previousPcm,
            pumpSuspended: pumpSuspended,
            calculationAvailable: calculationAvailable,
            cgmAvailable: cgmAvailable,
            closedLoopPreferred: closedLoopPreferred,
            sufficientClosedLoopParams: sufficientClosedLoopParams
        )
        self.currentPcm = currentPcm
        self.previousPcm = previousPcm
        self.pumpSuspendedRaw = pumpSuspended
        self.calculationAvailableRaw = calculationAvailable
        self.cgmAvailableRaw = cgmAvailable
        self.closedLoopPreferredRaw = closedLoopPreferred
        self.sufficientClosedLoopParamsRaw = sufficientClosedLoopParams
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentPcm: Int,
        previousPcm: Int,
        pumpSuspended: Int,
        calculationAvailable: Int,
        cgmAvailable: Int,
        closedLoopPreferred: Int,
        sufficientClosedLoopParams: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(currentPcm & 0xFF)]),
                Data([UInt8(previousPcm & 0xFF)]),
                Data([UInt8(pumpSuspended & 0xFF)]),
                Data([UInt8(calculationAvailable & 0xFF)]),
                Data([UInt8(cgmAvailable & 0xFF)]),
                Data([UInt8(closedLoopPreferred & 0xFF)]),
                Data([UInt8(sufficientClosedLoopParams & 0xFF)])
            )
        )
    }

    public var description: String {
        "ControlIQPcmChangeHistoryLog(cargo=\(cargo.hexadecimalString), currentPcm=\(currentPcm), previousPcm=\(previousPcm), pumpSuspendedRaw=\(pumpSuspendedRaw), calculationAvailableRaw=\(calculationAvailableRaw), cgmAvailableRaw=\(cgmAvailableRaw), closedLoopPreferredRaw=\(closedLoopPreferredRaw), sufficientClosedLoopParamsRaw=\(sufficientClosedLoopParamsRaw))"
    }
}
