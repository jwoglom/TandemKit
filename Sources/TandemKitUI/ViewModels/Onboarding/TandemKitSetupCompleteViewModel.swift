import Combine
import Foundation

/// Setup's writes, after the Load Pump History step has read the pump as its last user left it:
/// Control-IQ off, the host's settings, a sync, the chosen history load, then the host gets the manager.
class TandemKitSetupCompleteViewModel: ObservableObject {
    @Published var isFinished = false
    @Published var isLoadingHistory = false
    /// 0 to 1, never moving back.
    @Published var progress: Double = 0
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
        pumpManager.applyOnboardingSettings { failure in
            guard let failure else {
                self.finishSetup()
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

    var loadingMessage: String {
        String(format: String(
            localized: "Reading the past %1$@ hours of your pump's history into %2$@. Keep the pump near your phone.",
            comment: "Setup message while the pump's history loads (1: number of hours, 2: app name)"
        ), String(Int(TandemPumpManager.setupHistoryLoadWindow / .hours(1))), HostApp.current.appName)
    }

    func loadHistory() {
        isLoadingHistory = true
        pumpManager.loadHistoryForSetup(
            progress: { value in
                DispatchQueue.main.async {
                    self.progress = max(self.progress, value)
                }
            },
            completion: { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case let .success(summary):
                        self.progress = 1
                        self.isLoadingHistory = false
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
        isFinished = true
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
