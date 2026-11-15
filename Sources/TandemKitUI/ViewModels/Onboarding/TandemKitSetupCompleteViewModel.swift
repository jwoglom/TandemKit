import Combine
import Foundation

/// Setup's writes, after the Load Pump History step has read the pump as its last user left it:
/// Control-IQ off, the host's settings, a sync, the chosen history load, then the host gets the manager.
class TandemKitSetupCompleteViewModel: ObservableObject {
    enum Step: Int {
        case checkingPump
        case savingSettings
        case syncing
        case loadingHistory
        case finished
    }

    /// Stays `.loadingHistory` behind the load's summary, so the screen does not change under the alert.
    @Published private(set) var step: Step = .checkingPump
    /// Across every step, 0 to 1, never moving back.
    @Published private(set) var progress: Double = 0
    @Published var isShowingLoadFailedAlert = false
    @Published var loadFailedMessage: String?
    @Published var isShowingLoadSummary = false
    @Published var loadSummaryMessage: String?
    @Published var isSettingsError = false
    @Published var settingsErrorMessage: String?
    @Published var isPromptingControlIQOff = false
    @Published var isControlIQOffError = false
    @Published var controlIQOffErrorMessage: String?

    private let log = TandemLogger(category: "TandemKitSetupCompleteViewModel")
    private let pumpManager: TandemPumpManager
    private let loadsHistory: Bool
    private let pumpIsSetUp: () -> Void
    private var hasStarted = false

    init(pumpManager: TandemPumpManager, loadsHistory: Bool, pumpIsSetUp: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.loadsHistory = loadsHistory
        self.pumpIsSetUp = pumpIsSetUp
    }

    var isFinished: Bool { step == .finished }

    /// The load reads far more from the pump than the steps before it, which get a fifth of the bar.
    private var shareBeforeHistory: Double { loadsHistory ? 0.2 : 1 }

    private func enter(_ step: Step, historyProgress: Double = 0) {
        self.step = step
        let stepsBeforeHistory = Double(Step.loadingHistory.rawValue)
        let overall: Double
        switch step {
        case .checkingPump, .savingSettings, .syncing:
            overall = shareBeforeHistory * Double(step.rawValue) / stepsBeforeHistory
        case .loadingHistory:
            overall = shareBeforeHistory + (1 - shareBeforeHistory) * historyProgress
        case .finished:
            overall = 1
        }
        progress = max(progress, overall)
    }

    static func title(for step: Step) -> String {
        step == .finished
            ? String(localized: "Setup Complete", comment: "Title for setup complete")
            : String(localized: "Finishing Setup", comment: "Title for the last setup step while it writes to the pump")
    }

    var header: String {
        isFinished
            ? String(localized: "Your Tandem pump is connected!", comment: "Tandem setup complete message")
            : String(localized: "Finishing your pump's setup", comment: "Setup header while setup writes to the pump and reads it")
    }

    var stepMessage: String {
        switch step {
        case .checkingPump:
            return String(localized: "Checking the pump's settings.", comment: "Setup step that reads whether the pump runs Control-IQ")
        case .savingSettings:
            return String(localized: "Saving your settings to the pump.", comment: "Setup step that writes the app's basal rates, delivery limits and time to the pump")
        case .syncing:
            return String(localized: "Reading the pump's current status.", comment: "Setup step that syncs with the pump")
        case .loadingHistory:
            return String(format: String(
                localized: "Reading the past %1$@ hours of your pump's history into %2$@.",
                comment: "Setup message while the pump's history loads (1: number of hours, 2: app name)"
            ), String(Int(TandemPumpManager.setupHistoryLoadWindow / .hours(1))), HostApp.current.appName)
        case .finished:
            return String(format: String(
                localized:
                "You can now use your Tandem pump with %@. Make sure to keep your pump nearby and within Bluetooth range.",
                comment: "Tandem setup complete instructions"
            ), HostApp.current.appName)
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        pumpManager.controlIQNeedsTurningOffForSetup { needsTurningOff in
            DispatchQueue.main.async {
                if needsTurningOff {
                    self.isPromptingControlIQOff = true
                } else {
                    self.applyOnboardingSettings()
                }
            }
        }
    }

    var controlIQOffPromptMessage: String {
        String(format: String(
            localized: "The pump currently has Control-IQ on. Continuing will turn Control-IQ off, so that %@ uses its own algorithm to control insulin delivery.",
            comment: "Setup message when the paired pump is running Control-IQ (1: app name)"
        ), HostApp.current.appName)
    }

    func turnOffControlIQ() {
        pumpManager.turnOffControlIQForSetup { error in
            DispatchQueue.main.async {
                guard let error else {
                    self.applyOnboardingSettings()
                    return
                }
                self.controlIQOffErrorMessage = Self.controlIQOffFailureMessage(for: error)
                self.isControlIQOffError = true
            }
        }
    }

    static func controlIQOffFailureMessage(for error: Error) -> String {
        let summary = String(format: String(
            localized: "Control-IQ is still on, and setup can't finish until it is off so that %@ can control insulin delivery. Keep the pump near your phone and try again.",
            comment: "Setup error when turning Control-IQ off did not reach the pump (1: app name)"
        ), HostApp.current.appName)
        return "\(summary)\n\n\(error.localizedDescription)"
    }

    /// On failure, setup waits on the alert instead of advancing, because the pump would otherwise
    /// be left running basal rates the app doesn't know about (#206).
    func applyOnboardingSettings() {
        enter(.savingSettings)
        pumpManager.applyOnboardingSettings { failure in
            guard let failure else {
                DispatchQueue.main.async {
                    self.finishSetup()
                }
                return
            }

            self.log.error(
                "Failed to apply onboarding settings: basal \(failure.basalSchedule?.localizedDescription ?? "ok"), limits \(failure.deliveryLimits?.localizedDescription ?? "ok")"
            )
            DispatchQueue.main.async {
                self.settingsErrorMessage = Self.message(for: failure)
                self.isSettingsError = true
            }
        }
    }

    func continueWithoutOnboardingSettings() {
        log.error("Continuing setup with the pump holding settings the app could not write")
        finishSetup()
    }

    /// The load after the sync: its reports reach Loop's doses only under the boundary a sync gives.
    private func finishSetup() {
        enter(.syncing)
        pumpManager.syncPumpData { _ in
            DispatchQueue.main.async {
                if self.loadsHistory {
                    self.loadHistory()
                } else {
                    self.handOver()
                }
            }
        }
    }

    func loadHistory() {
        enter(.loadingHistory)
        pumpManager.loadHistoryForSetup(
            progress: { value in
                DispatchQueue.main.async {
                    self.enter(.loadingHistory, historyProgress: value)
                }
            },
            completion: { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case let .success(summary):
                        self.enter(.loadingHistory, historyProgress: 1)
                        self.loadSummaryMessage = Self.message(for: summary)
                        self.isShowingLoadSummary = true
                    case let .failure(error):
                        self.loadFailedMessage = error.localizedDescription
                        self.isShowingLoadFailedAlert = true
                    }
                }
            }
        )
    }

    func loadSummaryAcknowledged() {
        handOver()
    }

    static func message(for summary: SetupHistoryLoadSummary) -> String {
        let appName = HostApp.current.appName
        return String(format: String(
            localized: "Successfully processed %1$d pump bolus records and %2$d pump basal records from your Tandem Mobi. %3$d bolus records and %4$d basal records were added to %5$@.\n\nTo check what was imported, go to %5$@'s insulin treatments page.",
            comment: "Setup alert after the pump's history loaded (1: the pump's bolus records read, 2: its basal records read, 3: bolus records reported to the app, 4: basal records reported to the app, 5: app name)"
        ), summary.pumpBolusRecords, summary.pumpBasalRecords, summary.reportedBolusRecords, summary.reportedBasalRecords, appName)
    }

    private func handOver() {
        log.info("Pump set up")
        pumpIsSetUp()
        enter(.finished)
    }

    static func message(for failure: OnboardingSettingsFailure) -> String {
        let summary: String
        switch (failure.basalSchedule, failure.deliveryLimits) {
        case (.some, .some):
            summary = String(
                localized: "Your basal rates and delivery limits were not saved to the pump. The pump is still using its own settings, so it may not deliver what the app shows. The app will not set temporary basal rates until your basal rates are saved to the pump.",
                comment: "Setup error when neither the basal schedule nor the delivery limits reached the pump"
            )
        case (.some, .none):
            summary = String(
                localized: "Your basal rates were not saved to the pump. The pump is still using its own basal rates, so it may not deliver what the app shows. The app will not set temporary basal rates until your basal rates are saved to the pump.",
                comment: "Setup error when the basal schedule did not reach the pump"
            )
        default:
            summary = String(
                localized: "Your delivery limits were not saved to the pump. The pump is still using its own maximum basal and bolus limits.",
                comment: "Setup error when the delivery limits did not reach the pump"
            )
        }

        guard let detail = failure.basalSchedule ?? failure.deliveryLimits else {
            return summary
        }
        return "\(summary)\n\n\(detail.localizedDescription)"
    }
}
