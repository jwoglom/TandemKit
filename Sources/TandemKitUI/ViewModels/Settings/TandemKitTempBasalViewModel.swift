import Combine
import Foundation
import LoopKit

class TandemKitTempBasalViewModel: ObservableObject {
    enum RateView: Hashable {
        case percent
        case units
    }

    enum Screen: Equatable {
        case loading
        case unreachable
        case suspended
        case form
        case active(TempRateStatus)
    }

    @Published private(set) var screen: Screen = .loading {
        didSet { onTitleChange?(title) }
    }

    @Published private(set) var profileBasalRate: Double = 0
    @Published var percent = ManualTempBasalForm.defaultPercent
    @Published var rateView: RateView = .percent
    @Published var hours = Int(ManualTempBasalForm.defaultDuration.minutes) / 60
    @Published var minutes = Int(ManualTempBasalForm.defaultDuration.minutes) % 60
    @Published private(set) var isSending = false
    @Published var showingSetConfirmation = false
    @Published var showingStopConfirmation = false
    @Published var failure: ErrorSheetContent?

    var onTitleChange: ((String) -> Void)?

    private let pumpManager: TandemPumpManager?
    private var reloadTimer: Timer?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    deinit {
        reloadTimer?.invalidate()
    }

    var title: String {
        if case .active = screen {
            return String(localized: "Active temp rate", comment: "Title of the temp basal screen while a temp rate runs")
        }
        return String(localized: "Set temp basal", comment: "The settings row that opens the temp basal screen, and its title while no temp rate runs")
    }

    // MARK: - The form

    var duration: TimeInterval {
        ManualTempBasalForm.duration(hours: hours, minutes: minutes)
    }

    var acceptedPercents: ClosedRange<Int>? {
        pumpManager?.manualTempBasalPercents(for: duration, profileBasalRate: profileBasalRate)
    }

    var isPercentValid: Bool {
        ManualTempBasalForm.isValid(percent, accepted: acceptedPercents)
    }

    var isDurationValid: Bool {
        ManualTempBasalForm.isValid(duration: duration)
    }

    var canSet: Bool {
        !isSending && ManualTempBasalForm.canSet(percent, accepted: acceptedPercents, duration: duration)
    }

    var rate: Double {
        ManualTempBasalForm.rate(percent: percent, profileBasalRate: profileBasalRate)
    }

    var canStepUp: Bool {
        !isSending && ManualTempBasalForm.stepUp(from: percent, accepted: acceptedPercents) != nil
    }

    var canStepDown: Bool {
        !isSending && ManualTempBasalForm.stepDown(from: percent, accepted: acceptedPercents) != nil
    }

    func stepUp() {
        if let next = ManualTempBasalForm.stepUp(from: percent, accepted: acceptedPercents) {
            percent = next
        }
    }

    func stepDown() {
        if let next = ManualTempBasalForm.stepDown(from: percent, accepted: acceptedPercents) {
            percent = next
        }
    }

    /// A rate typed in the unit view, kept as the whole percent nearest it.
    func setRate(_ unitsPerHour: Double) {
        if let typed = ManualTempBasalForm.percent(forRate: unitsPerHour, profileBasalRate: profileBasalRate) {
            percent = typed
        }
    }

    /// From now to the end of the duration; empty while the duration is one the pump refuses.
    var effectiveBasalRates: [ManualTempBasalForm.EffectiveRate] {
        guard let pumpManager, isDurationValid else { return [] }
        let start = pumpManager.now
        return ManualTempBasalForm.effectiveRates(
            percent: percent,
            profileBasalRate: profileBasalRate,
            segmentChanges: pumpManager.pumpSegmentChanges(after: start, through: start.addingTimeInterval(duration)),
            from: start,
            duration: duration
        )
    }

    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: duration) ?? ""
    }

    var setConfirmationMessage: String {
        String(
            format: String(
                localized: "Set a temp rate for %1$d%% of profile basal for a duration of %2$@?\n\nYour new effective basal rate will be %3$@ U/hr.",
                comment: "Confirmation before setting a temp basal (1: percent of the profile, 2: the duration, 3: the rate that runs now)"
            ),
            percent,
            durationText,
            Self.rateText(rate)
        )
    }

    func stopConfirmationMessage(percent: Int) -> String {
        String(
            format: String(
                localized: "Stop the active temp rate of %d%%?",
                comment: "Confirmation before stopping the temp basal that runs (the percent of the profile)"
            ),
            percent
        )
    }

    static func rateText(_ unitsPerHour: Double) -> String {
        String(format: "%.2f", unitsPerHour)
    }

    // MARK: - The pump

    func load() {
        guard let pumpManager else {
            screen = .unreachable
            return
        }
        if case .form = screen {} else {
            screen = .loading
        }
        pumpManager.readTempRateStatus { result in
            DispatchQueue.main.async {
                self.apply(result)
            }
        }
    }

    func apply(_ result: Result<TempRateStatus, PumpManagerError>) {
        reloadTimer?.invalidate()
        reloadTimer = nil
        guard case let .success(status) = result else {
            screen = .unreachable
            return
        }
        profileBasalRate = status.profileBasalRate
        if status.isSuspended {
            screen = .suspended
        } else if status.isActive, !status.isReplaceable {
            screen = .active(status)
            scheduleReload(at: status.endDate)
        } else {
            screen = .form
        }
    }

    /// The temp runs out on the pump on its own; a reading just after says so.
    private func scheduleReload(at end: Date?) {
        guard let end else { return }
        let fire = max(end, Date()).addingTimeInterval(5)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            self?.load()
        }
        RunLoop.main.add(timer, forMode: .common)
        reloadTimer = timer
    }

    func set() {
        guard let pumpManager, canSet else { return }
        isSending = true
        pumpManager.enactManualTempBasal(percent: percent, duration: duration) { error in
            DispatchQueue.main.async {
                self.isSending = false
                if let error {
                    self.failure = Self.setFailure(error)
                }
                self.load()
            }
        }
    }

    func stop() {
        guard let pumpManager else { return }
        isSending = true
        pumpManager.stopTempBasalFromSettings { error in
            DispatchQueue.main.async {
                self.isSending = false
                if let error {
                    self.failure = ErrorSheetContent(
                        title: String(localized: "Could not stop temp rate", comment: "Title for failure to stop temp rate"),
                        message: Self.message(for: error)
                    )
                }
                self.load()
            }
        }
    }

    static func setFailure(_ error: PumpManagerError) -> ErrorSheetContent {
        let title = String(localized: "Could not set temp rate", comment: "Title for failure to set a temp basal from the temp basal screen")
        if case let .deviceState(underlying?) = error,
           underlying as? TandemPumpManagerValidationError == .tempBasalAlreadyRunning
        {
            return ErrorSheetContent(
                title: title,
                message: String(
                    localized: "A temp rate started while you were on this screen.",
                    comment: "Message when a temp basal set from the temp basal screen finds another temp started since the screen loaded"
                )
            )
        }
        return ErrorSheetContent(title: title, message: message(for: error))
    }

    static func message(for error: Error) -> String {
        [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
