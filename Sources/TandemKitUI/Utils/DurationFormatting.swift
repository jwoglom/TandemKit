import Foundation

/// Formats a duration as at most two units, largest first, eliding zero units:
/// `9d 4h`, `10d`, `4h 21m`, `21m`, `0m`.
func formatCompactDuration(seconds: UInt32) -> String {
    let totalMinutes = Int(seconds) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return hours > 0
            ? String(format: String(localized: "%dd %dh", comment: "Compact duration in days and hours"), days, hours)
            : String(format: String(localized: "%dd", comment: "Compact duration in days"), days)
    }
    if hours > 0 {
        return minutes > 0
            ? String(format: String(localized: "%dh %dm", comment: "Compact duration in hours and minutes"), hours, minutes)
            : String(format: String(localized: "%dh", comment: "Compact duration in hours"), hours)
    }
    return String(format: String(localized: "%dm", comment: "Compact duration in minutes"), minutes)
}

/// Compact duration between `date` and now. Negative intervals (pump clock skew can place a
/// timestamp slightly in the future) are clamped to zero.
func formatCompactDuration(since date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    return formatCompactDuration(seconds: UInt32(max(0, elapsed)))
}

/// Long-form duration between `date` and now: `4 days, 21 hours`.
func formatDurationToDaysHours(since date: Date) -> String {
    let components = Calendar.current.dateComponents([.day, .hour], from: date, to: Date())
    let days = components.day ?? 0
    let hours = components.hour ?? 0

    let dayString = days == 1 ? String(localized: "day", comment: "Singular day unit") : String(localized: "days", comment: "Plural days unit")
    let hourString = hours == 1 ? String(localized: "hour", comment: "Singular hour unit") : String(localized: "hours", comment: "Plural hours unit")

    return "\(days) \(dayString), \(hours) \(hourString)"
}
