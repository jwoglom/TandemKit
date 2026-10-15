import Foundation

/// What the pump was delivering the last time the driver heard from it, which is what it goes on
/// doing out of reach: a temp basal runs to its programmed end, then the profile.
public struct LastKnownBasalDelivery: Equatable {
    public enum Delivery: Equatable {
        case profile(unitsPerHour: Double)
        case tempBasal(unitsPerHour: Double, endDate: Date, profileUnitsPerHourAfter: Double)
        case suspended
        case controlIQ
    }

    /// The phone's clock.
    public let lastContact: Date
    public let delivery: Delivery

    public init(lastContact: Date, delivery: Delivery) {
        self.lastContact = lastContact
        self.delivery = delivery
    }

    public func localizedDescription(
        appName: String,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let ago = Self.elapsedDescription(now.timeIntervalSince(lastContact))
        switch delivery {
        case let .profile(rate):
            return String(
                format: String(
                    localized: "%1$@ last connected to your pump %2$@. At that time, the pump was delivering basal at the profile basal rate of %3$@ U/hr and will continue to deliver basal as programmed until reconnected.",
                    comment: "Pump disconnected detail with no temp basal running; the placeholders are the app's name, how long ago it last connected, and the profile basal rate"
                ),
                appName,
                ago,
                Self.rateText(rate)
            )
        case let .tempBasal(rate, endDate, profileRate) where now < endDate:
            return String(
                format: String(
                    localized: "%1$@ last connected to your pump %2$@. At that time, the pump was delivering basal at a temp rate of %3$@ U/hr, and will return to the profile basal rate of %4$@ U/hr at %5$@ if not reconnected.",
                    comment: "Pump disconnected detail while a temp basal is still running; the placeholders are the app's name, how long ago it last connected, the temp rate, the profile basal rate after it, and when the temp ends"
                ),
                appName,
                ago,
                Self.rateText(rate),
                Self.rateText(profileRate),
                Self.timeText(endDate, now: now, locale: locale, timeZone: timeZone)
            )
        case let .tempBasal(rate, endDate, profileRate):
            return String(
                format: String(
                    localized: "%1$@ last connected to your pump %2$@. At that time, the pump was delivering basal at %3$@ U/hr with a planned end time of %4$@. We expect the pump to have returned to its profile basal rate of %5$@ U/hr and it will continue as programmed until reconnected.",
                    comment: "Pump disconnected detail once the temp basal it last saw has reached its end; the placeholders are the app's name, how long ago it last connected, the temp rate, when the temp ended, and the profile basal rate after it"
                ),
                appName,
                ago,
                Self.rateText(rate),
                Self.timeText(endDate, now: now, locale: locale, timeZone: timeZone),
                Self.rateText(profileRate)
            )
        case .suspended:
            return String(
                format: String(
                    localized: "%1$@ last connected to your pump %2$@. At that time, insulin delivery was suspended. %1$@ cannot tell whether it has been resumed since.",
                    comment: "Pump disconnected detail while delivery was suspended; the placeholders are the app's name and how long ago it last connected"
                ),
                appName,
                ago
            )
        case .controlIQ:
            return String(
                format: String(
                    localized: "%1$@ last connected to your pump %2$@. At that time, the pump's Control-IQ algorithm was adjusting basal delivery, and it keeps running on the pump whether or not %1$@ is connected.",
                    comment: "Pump disconnected detail while the pump's own algorithm runs; the placeholders are the app's name and how long ago it last connected"
                ),
                appName,
                ago
            )
        }
    }

    static func elapsedDescription(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        guard minutes > 0 else {
            return String(localized: "less than a minute ago", comment: "How long ago the pump last connected, under a minute")
        }

        let parts: [String]
        if minutes < 60 {
            parts = [Self.minutes(minutes)]
        } else if minutes < 24 * 60 {
            parts = [Self.hours(minutes / 60)] + (minutes % 60 > 0 ? [Self.minutes(minutes % 60)] : [])
        } else {
            let hours = minutes / 60
            parts = [Self.days(hours / 24)] + (hours % 24 > 0 ? [Self.hours(hours % 24)] : [])
        }
        return String(
            format: String(localized: "%@ ago", comment: "How long ago the pump last connected; the placeholder is a duration"),
            parts.joined(separator: " ")
        )
    }

    private static func minutes(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 minute", comment: "A duration of one minute")
            : String(format: String(localized: "%d minutes", comment: "A duration in minutes"), count)
    }

    private static func hours(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 hour", comment: "A duration of one hour")
            : String(format: String(localized: "%d hours", comment: "A duration in hours"), count)
    }

    private static func days(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 day", comment: "A duration of one day")
            : String(format: String(localized: "%d days", comment: "A duration in days"), count)
    }

    private static func rateText(_ unitsPerHour: Double) -> String {
        String(format: "%.2f", unitsPerHour)
    }

    /// A temp can run 72 hours, so an end more than half a day off carries its date.
    private static func timeText(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = abs(date.timeIntervalSince(now)) < .hours(12) ? .none : .medium
        return formatter.string(from: date)
    }
}

public extension TandemPumpManager {
    /// Nil when the driver can't say what the pump runs: it has never synced, the pump's clock or
    /// profile can't be placed against the host's schedule, or the pump runs a temp whose end only
    /// history gives.
    var lastKnownBasalDelivery: LastKnownBasalDelivery? {
        guard let lastContact = state.lastReconciliation else {
            return nil
        }

        let dose = state.basalDose
        if dose.type == .suspend {
            return LastKnownBasalDelivery(lastContact: lastContact, delivery: .suspended)
        }
        if state.useControlIQ {
            return LastKnownBasalDelivery(lastContact: lastContact, delivery: .controlIQ)
        }

        guard state.hasSyncedBasalRateSchedule,
              state.basalProfileUpdateStatus == .none,
              !state.isPumpClockUntrusted,
              state.basalRateSchedule.items.contains(where: { $0.value > 0 }),
              state.deliveryTransitions.pending?.replacement == nil
        else {
            return nil
        }

        switch dose.type {
        case .tempBasal where dose.estimatedEndDate > lastContact:
            // Once the temp ends the pump runs its own profile on its own clock, skewed or not.
            let profileRate = getScheduledBasalRate(at: dose.estimatedEndDate.addingTimeInterval(state.pumpClockOffset))
            return LastKnownBasalDelivery(
                lastContact: lastContact,
                delivery: .tempBasal(unitsPerHour: dose.value, endDate: dose.estimatedEndDate, profileUnitsPerHourAfter: profileRate)
            )
        default:
            return LastKnownBasalDelivery(
                lastContact: lastContact,
                delivery: .profile(unitsPerHour: scheduledBasalRateInForce(at: lastContact))
            )
        }
    }
}
