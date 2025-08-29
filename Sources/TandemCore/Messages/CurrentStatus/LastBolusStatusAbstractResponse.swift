//
//  LastBolusStatusAbstractResponse.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Shared fields for last bolus status responses.
//  Based on PumpX2's LastBolusStatusAbstractResponse.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/LastBolusStatusAbstractResponse.java
//

import Foundation

/// Protocol capturing fields common to last bolus status responses.
public protocol LastBolusStatusAbstractResponse: StatusMessage {
    var bolusId: Int { get }
    var timestamp: UInt32 { get }
    var deliveredVolume: UInt32 { get }
    var bolusStatusId: Int { get }
    var bolusSourceId: Int { get }
    var bolusTypeBitmask: Int { get }
    var extendedBolusDuration: UInt32 { get }
}

public enum LastBolusStatusAbstractResponseBolusStatus: Int {
    case stopped = 0
    case complete = 3
}

public extension LastBolusStatusAbstractResponse {
    typealias BolusStatus = LastBolusStatusAbstractResponseBolusStatus

    var bolusSource: BolusSource? { BolusSource.fromId(bolusSourceId) }
    var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }
    var bolusStatus: BolusStatus? { BolusStatus(rawValue: bolusStatusId) }
    var timestampDate: Date { Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp)) }
}

