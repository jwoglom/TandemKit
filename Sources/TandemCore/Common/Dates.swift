import Foundation

struct Dates {
    static let JANUARY_1_2008_UNIX_EPOCH: TimeInterval = 1_199_145_600

    static func fromJan12008ToUnixEpochSeconds(_ seconds: TimeInterval) -> TimeInterval {
        seconds + JANUARY_1_2008_UNIX_EPOCH
    }

    static func fromJan12008EpochSecondsToDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: fromJan12008ToUnixEpochSeconds(seconds))
    }

    static func fromInstantToJan12008EpochSeconds(_ date: Date) -> TimeInterval {
        date.timeIntervalSince1970 - JANUARY_1_2008_UNIX_EPOCH
    }

    private static let SECONDS_IN_DAY: TimeInterval = 60 * 60 * 24

    static func fromJan12008EpochDaysToDate(_ days: TimeInterval) -> Date {
        Date(timeIntervalSince1970: fromJan12008ToUnixEpochSeconds(days * SECONDS_IN_DAY))
    }
}
