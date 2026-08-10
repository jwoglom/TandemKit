import LoopKit
import SwiftUI

class TandemKitControlIQSettingsViewModel: ObservableObject {
    @Published var controlIQEnabled = false { didSet { checkDirtyState() } }
    @Published var weight: Int = 70 { didSet { checkDirtyState() } }
    @Published var totalDailyInsulin: Int = 30 { didSet { checkDirtyState() } }

    @Published var sleepSchedules: [SleepScheduleSlot] = []

    @Published var isFetching: Bool = true
    @Published var isDirty: Bool = false
    @Published var disabled: Bool = false
    @Published var isLoading: Bool = false
    @Published var saveError: String?

    private var originalEnabled: Bool = false
    private var originalWeight: Int = 70
    private var originalTDI: Int = 30

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        if let state = pumpManager?.state {
            controlIQEnabled = state.useControlIQ

            if let w = state.controlIQWeightLbs {
                weight = w
                originalWeight = w
            }
            if let tdi = state.controlIQTotalDailyInsulin {
                totalDailyInsulin = tdi
                originalTDI = tdi
            }
        }

        fetchCurrentSettings()
    }

    // MARK: - Fetch

    func fetchCurrentSettings() {
        isFetching = true

        pumpManager?.getControlIQData { ciqResponse, scheduleResponse in
            DispatchQueue.main.async {
                if let ciqResponse {
                    // The pump reports the weight in whichever unit it displays; the request always
                    // carries pounds, so normalize before it reaches the picker.
                    let weightLbs = ControlIQSettingsLimits.pounds(
                        from: ciqResponse.getWeight(),
                        unit: ciqResponse.weightUnit
                    )

                    self.controlIQEnabled = ciqResponse.getClosedLoopEnabled()
                    self.originalEnabled = ciqResponse.getClosedLoopEnabled()
                    // A pump with Control-IQ never configured reports zeroes, which are shown as
                    // they are: substituting a plausible-looking default here would let the user
                    // enable Control-IQ with a body weight they never entered. Saving with them
                    // fails, and now says which value is missing. Making them enterable is #223's
                    // remaining half.
                    self.weight = weightLbs
                    self.originalWeight = weightLbs
                    self.totalDailyInsulin = ciqResponse.getTotalDailyInsulin()
                    self.originalTDI = ciqResponse.getTotalDailyInsulin()
                    self.isDirty = false
                }

                if let scheduleResponse {
                    let slots = [
                        SleepScheduleSlot(from: scheduleResponse.schedule0),
                        SleepScheduleSlot(from: scheduleResponse.schedule1),
                        SleepScheduleSlot(from: scheduleResponse.schedule2),
                        SleepScheduleSlot(from: scheduleResponse.schedule3)
                    ]
                    self.sleepSchedules = slots
                }

                self.isFetching = false
            }
        }
    }

    // MARK: - Save ControlIQ Settings

    func saveControlIQSettings() {
        saveError = nil
        isLoading = true

        let request = ChangeControlIQSettingsRequest(
            enabled: controlIQEnabled,
            weightLbs: weight,
            totalDailyInsulinUnits: totalDailyInsulin
        )

        pumpManager?.configureControlIQMode(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success:
                    self.originalEnabled = self.controlIQEnabled
                    self.originalWeight = self.weight
                    self.originalTDI = self.totalDailyInsulin
                    self.isDirty = false
                case let .failure(error):
                    // Report what actually went wrong -- an unset weight or TDI, or the status the
                    // pump rejected the change with -- instead of blaming the connection.
                    self.saveError = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }
            }
        }
    }

    // MARK: - Save Sleep Schedule

    func saveSleepSchedule(slot: Int) {
        guard slot >= 0, slot < sleepSchedules.count else { return }
        isLoading = true

        let schedule = sleepSchedules[slot].toProtocol()
        pumpManager?.setSleepSchedule(slot: slot, schedule: schedule) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if !success {
                    self.saveError = String(
                        localized:
                        "Failed to update sleep schedule. Check pump connection.",
                        comment: "Error when sleep schedule save fails"
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkDirtyState() {
        DispatchQueue.main.async {
            self.isDirty = (
                self.controlIQEnabled != self.originalEnabled ||
                    self.weight != self.originalWeight ||
                    self.totalDailyInsulin != self.originalTDI
            )

            self.disabled = !self.isDirty
        }
    }
}

// MARK: - Sleep Schedule Model

struct SleepScheduleSlot: Identifiable {
    let id: Int
    var enabled: Bool
    var activeDays: Int
    var startTime: Int // minutes from midnight
    var endTime: Int // minutes from midnight

    init(from schedule: ControlIQSleepScheduleResponse.SleepSchedule, index: Int = 0) {
        id = index
        enabled = schedule.enabled != 0
        activeDays = schedule.activeDays
        startTime = schedule.startTime
        endTime = schedule.endTime
    }

    init(id: Int, enabled: Bool = false, activeDays: Int = 0, startTime: Int = 0, endTime: Int = 0) {
        self.id = id
        self.enabled = enabled
        self.activeDays = activeDays
        self.startTime = startTime
        self.endTime = endTime
    }

    func toProtocol() -> ControlIQSleepScheduleResponse.SleepSchedule {
        ControlIQSleepScheduleResponse.SleepSchedule(
            enabled: enabled ? 1 : 0,
            activeDays: activeDays,
            startTime: startTime,
            endTime: endTime
        )
    }

    var startTimeText: String {
        formatMinutes(startTime)
    }

    var endTimeText: String {
        formatMinutes(endTime)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    var activeDaysText: String {
        let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]
        var result: [String] = []
        for i in 0 ..< 7 {
            if activeDays & (1 << i) != 0 {
                result.append(dayLetters[i])
            }
        }
        return result.isEmpty ? "None" : result.joined(separator: " ")
    }
}
