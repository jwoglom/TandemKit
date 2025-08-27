//
//  Dates.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift port of pumpX2 Dates helper:
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/helpers/Dates.java
//

import Foundation

struct Dates {
    static let JANUARY_1_2008_UNIX_EPOCH: TimeInterval = 1199145600

    static func fromJan12008ToUnixEpochSeconds(_ seconds: TimeInterval) -> TimeInterval {
        return seconds + JANUARY_1_2008_UNIX_EPOCH
    }

    static func fromJan12008EpochSecondsToDate(_ seconds: TimeInterval) -> Date {
        return Date(timeIntervalSince1970: fromJan12008ToUnixEpochSeconds(seconds))
    }

    static func fromInstantToJan12008EpochSeconds(_ date: Date) -> TimeInterval {
        return date.timeIntervalSince1970 - JANUARY_1_2008_UNIX_EPOCH
    }

    private static let SECONDS_IN_DAY: TimeInterval = 60 * 60 * 24

    static func fromJan12008EpochDaysToDate(_ days: TimeInterval) -> Date {
        return Date(timeIntervalSince1970: fromJan12008ToUnixEpochSeconds(days * SECONDS_IN_DAY))
    }
}
