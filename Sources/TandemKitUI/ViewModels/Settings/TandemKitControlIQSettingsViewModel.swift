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

            if let w = state.controlIQWeight {
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isFetching = false }
                return
            }

            // Fetch ControlIQ info
            if let ciqResponse = pumpManager.sendMessage(message: ControlIQInfoV2Request()) as? ControlIQInfoV2Response {
                DispatchQueue.main.async {
                    self.controlIQEnabled = ciqResponse.closedLoopEnabled
                    self.weight = ciqResponse.weight
                    self.originalEnabled = ciqResponse.closedLoopEnabled
                    self.originalWeight = ciqResponse.weight
                    self.totalDailyInsulin = ciqResponse.totalDailyInsulin
                    self.originalTDI = ciqResponse.totalDailyInsulin
                    self.isDirty = false
                }
            }

            // Fetch sleep schedules
            if let scheduleResponse = pumpManager
                .sendMessage(message: ControlIQSleepScheduleRequest()) as? ControlIQSleepScheduleResponse
            {
                let slots = [
                    SleepScheduleSlot(from: scheduleResponse.schedule0),
                    SleepScheduleSlot(from: scheduleResponse.schedule1),
                    SleepScheduleSlot(from: scheduleResponse.schedule2),
                    SleepScheduleSlot(from: scheduleResponse.schedule3)
                ]
                DispatchQueue.main.async {
                    self.sleepSchedules = slots
                }
            }

            DispatchQueue.main.async {
                self.isFetching = false
            }
        }
    }

    // MARK: - Save ControlIQ Settings

    func saveControlIQSettings() {
        saveError = nil
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }

            let request = ChangeControlIQSettingsRequest(
                enabled: controlIQEnabled,
                weightLbs: self.weight,
                totalDailyInsulinUnits: self.totalDailyInsulin
            )

            pumpManager.configureControlIQMode(request) { success in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if success {
                        self.originalWeight = self.weight
                        self.originalTDI = self.totalDailyInsulin
                        self.isDirty = false
                    } else {
                        self.saveError = String(
                            localized:
                            "Failed to update Control-IQ settings. Check pump connection.",
                            comment: "Error when Control-IQ settings save fails"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Save Sleep Schedule

    func saveSleepSchedule(slot: Int) {
        guard slot >= 0, slot < sleepSchedules.count else { return }
        isLoading = true

        let schedule = sleepSchedules[slot].toProtocol()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }

            let response = self.pumpManager?.sendMessage(message: SetSleepScheduleRequest(
                slot: slot,
                schedule: schedule,
                flag: 1
            )) as? SetSleepScheduleResponse

            DispatchQueue.main.async {
                self.isLoading = false
                if response?.isStatusOK != true {
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
