//
//  CurrentEGVGuiData.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CurrentEGVGuiDataRequest and CurrentEGVGuiDataResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CurrentEGVGuiDataRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CurrentEGVGuiDataResponse.java
//

import Foundation

/// Request the current CGM reading.
public class CurrentEGVGuiDataRequest: Message {
    public static let props = MessageProps(
        opCode: 34,
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

/// Response with the current CGM reading and trend information.
public class CurrentEGVGuiDataResponse: Message {
    public static let props = MessageProps(
        opCode: 35,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bgReadingTimestampSeconds: UInt32
    public var cgmReading: Int
    public var egvStatusId: Int
    public var trendRate: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bgReadingTimestampSeconds = Bytes.readUint32(cargo, 0)
        self.cgmReading = Bytes.readShort(cargo, 4)
        self.egvStatusId = Int(cargo[6])
        self.trendRate = Int(cargo[7])
    }

    public init(bgReadingTimestampSeconds: UInt32, cgmReading: Int, egvStatusId: Int, trendRate: Int) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(bgReadingTimestampSeconds),
            Bytes.firstTwoBytesLittleEndian(cgmReading),
            Bytes.firstByteLittleEndian(egvStatusId),
            Bytes.firstByteLittleEndian(trendRate)
        )
        self.bgReadingTimestampSeconds = bgReadingTimestampSeconds
        self.cgmReading = cgmReading
        self.egvStatusId = egvStatusId
        self.trendRate = trendRate
    }

    public var egvStatus: EGVStatus? {
        return EGVStatus(rawValue: egvStatusId)
    }

    public enum EGVStatus: Int {
        case INVALID = 0
        case VALID = 1
        case LOW = 2
        case HIGH = 3
        case UNAVAILABLE = 4
    }
}

