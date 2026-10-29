import Combine
import Foundation

/// Asks before setup writes anything, with what the pump read then; the load itself runs after the
/// setup sync (`TandemKitSetupCompleteViewModel`), whose reconciliation boundary its reports need.
final class TandemKitLoadHistoryViewModel: ObservableObject {
    @Published var isShowingNotLoadedAlert = false

    let reading: SetupDeliveryReading
    private let now: () -> Date
    /// Whether the user chose to load.
    private let done: (Bool) -> Void

    init(reading: SetupDeliveryReading, now: @escaping () -> Date = Date.init, done: @escaping (Bool) -> Void) {
        self.reading = reading
        self.now = now
        self.done = done
    }

    var appName: String { HostApp.current.appName }

    var introduction: String {
        String(
            localized: "The Tandem Mobi you just connected reports the following insulin delivery information:",
            comment: "Setup introduction to what the paired pump reports about its insulin delivery"
        )
    }

    /// One line per reading the pump answered.
    var readings: [String] {
        var lines: [String] = []
        if let insulinOnBoard = reading.insulinOnBoard {
            lines.append(String(format: String(
                localized: "Insulin on Board: %@ units",
                comment: "Setup line with the pump's insulin on board (1: units, to two decimals)"
            ), String(format: "%.2f", insulinOnBoard)))
        }
        if case let .delivered(at) = reading.lastBolus {
            lines.append(String(format: String(
                localized: "Last bolus delivery: %1$@ (%2$@)",
                comment: "Setup line with the pump's last bolus (1: time of day, 2: how long ago)"
            ), Self.timeFormatter.string(from: at), LastKnownBasalDelivery.elapsedDescription(now().timeIntervalSince(at))))
        }
        if reading.isSuspended {
            lines.append(String(
                localized: "Insulin delivery currently suspended",
                comment: "Setup line when the paired pump has insulin delivery suspended"
            ))
        } else if let rate = reading.currentBasalRate {
            lines.append(String(format: String(
                localized: "Current basal rate: %@ u/hr",
                comment: "Setup line with the pump's current basal rate (1: units per hour, to two decimals)"
            ), String(format: "%.2f", rate)))
        }
        return lines
    }

    var question: String {
        guard !readings.isEmpty else {
            return String(format: String(
                localized: "Would you like to load the pump's insulin delivery history into %@ so it is included in your IOB?",
                comment: "Setup question whether to load the pump's history, when it reported no delivery readings (1: app name)"
            ), appName)
        }
        return String(format: String(
            localized: "Would you like to load this insulin delivery information into %@ so it is included in your IOB?",
            comment: "Setup question whether to load the pump's history (1: app name)"
        ), appName)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var loadButtonTitle: String {
        String(format: String(
            localized: "Load Pump History into %@",
            comment: "Setup button that loads the pump's history into the app (1: app name)"
        ), appName)
    }

    var notLoadedMessage: String {
        // "this app" opens the sentence for a host that is neither Trio nor Loop.
        let sentenceStart = appName.prefix(1).uppercased() + appName.dropFirst()
        return String(format: String(
            localized: "%@ will not count insulin this pump delivered before you connected it.",
            comment: "Setup alert after the user chose not to load the pump's history (1: app name at the start of a sentence)"
        ), sentenceStart)
    }

    func doNotLoad() {
        isShowingNotLoadedAlert = true
    }

    func notLoadedAcknowledged() {
        done(false)
    }

    func load() {
        done(true)
    }
}
