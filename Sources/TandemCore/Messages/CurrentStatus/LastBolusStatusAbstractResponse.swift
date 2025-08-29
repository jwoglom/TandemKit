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

public extension LastBolusStatusAbstractResponse {
    var bolusSource: BolusSource? { BolusSource.fromId(bolusSourceId) }
    var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }
    var timestampDate: Date { Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp)) }
}

