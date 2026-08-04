import LoopKit
import SwiftUI

class TandemKitControlIQSettingsViewModel: ObservableObject {
    @Published var controlIQEnabled = false { didSet { checkDirtyState() } }

    /// Body weight as stored on the pump, expressed in `weightUnit`. `nil` means the
    /// pump has never had one configured — the user has to supply one before
    /// Control-IQ can be turned on, and we must not invent a value on their behalf.
    @Published var weight: Int? { didSet { checkDirtyState() } }

    /// Total daily insulin in whole units, or `nil` when never configured.
    @Published var totalDailyInsulin: Int? { didSet { checkDirtyState() } }

    /// Unit the pump reports its stored weight in. Defaults to pounds only until the
    /// pump tells us otherwise.
    @Published var weightUnit: ControlIQWeightUnit = .pounds

    @Published var sleepSchedules: [SleepScheduleSlot] = []

    @Published var isFetching: Bool = true
    @Published var isDirty: Bool = false
    @Published var disabled: Bool = true
    @Published var isLoading: Bool = false
    @Published var saveError: String?

    private var originalEnabled: Bool = false
    private var originalWeight: Int?
    private var originalTDI: Int?

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        if let state = pumpManager?.state {
            controlIQEnabled = state.useControlIQ
            originalEnabled = state.useControlIQ
            weight = state.controlIQWeight
            originalWeight = state.controlIQWeight
            totalDailyInsulin = state.controlIQTotalDailyInsulin
            originalTDI = state.controlIQTotalDailyInsulin
            if let unit = state.controlIQWeightUnit {
                weightUnit = unit
            }
        }

        checkDirtyState()
        fetchCurrentSettings()
    }

    // MARK: - Validation

    /// Range the weight picker offers, in the pump's own unit.
    var weightRange: ClosedRange<Int> { ControlIQSettingsLimits.weightRange(for: weightUnit) }

    var totalDailyInsulinRange: ClosedRange<Int> { ControlIQSettingsLimits.totalDailyInsulinRange }

    var weightUnitLabel: String {
        weightUnit == .pounds
            ? String(localized: "lbs", comment: "Abbreviation for pounds")
            : String(localized: "kg", comment: "Abbreviation for kilograms")
    }

    /// The reason the current values cannot be saved, or `nil` when they can.
    ///
    /// Shown in the UI *before* the user taps Save, so a pump that would reject the
    /// change is never asked to.
    var validationError: Error? {
        do {
            try ControlIQSettingsLimits.validate(
                enabled: controlIQEnabled,
                weight: weight,
                weightUnit: weightUnit,
                totalDailyInsulin: totalDailyInsulin
            )
            return nil
        } catch {
            return error
        }
    }

    var validationMessage: String? { validationError?.localizedDescription }

    // MARK: - Fetch

    func fetchCurrentSettings() {
        isFetching = true

        pumpManager?.getControlIQData { ciqResponse, scheduleResponse in
            DispatchQueue.main.async {
                if let ciqResponse {
                    self.controlIQEnabled = ciqResponse.getClosedLoopEnabled()
                    self.originalEnabled = ciqResponse.getClosedLoopEnabled()

                    // The pump reports zero for a weight or TDD that has never been
                    // set. Carry that through as "not set" instead of showing 0 and
                    // echoing it back on save.
                    self.weight = ciqResponse.configuredWeight
                    self.originalWeight = ciqResponse.configuredWeight
                    self.totalDailyInsulin = ciqResponse.configuredTotalDailyInsulin
                    self.originalTDI = ciqResponse.configuredTotalDailyInsulin

                    if let unit = ciqResponse.weightUnit {
                        self.weightUnit = unit
                    }
                }

                if let scheduleResponse {
                    let slots = [
                        SleepScheduleSlot(from: scheduleResponse.schedule0, index: 0),
                        SleepScheduleSlot(from: scheduleResponse.schedule1, index: 1),
                        SleepScheduleSlot(from: scheduleResponse.schedule2, index: 2),
                        SleepScheduleSlot(from: scheduleResponse.schedule3, index: 3)
                    ]
                    self.sleepSchedules = slots
                }

                self.checkDirtyState()
                self.isFetching = false
            }
        }
    }

    // MARK: - Save ControlIQ Settings

    func saveControlIQSettings() {
        saveError = nil

        if let validationError {
            saveError = validationError.localizedDescription
            return
        }

        // Validation guarantees both values are present whenever Control-IQ is being
        // enabled. On the disable path they may still be missing, in which case we
        // send zero -- the same "not configured" the pump already holds -- rather
        // than inventing a weight the user never entered.
        let request = ChangeControlIQSettingsRequest(
            enabled: controlIQEnabled,
            weight: weight ?? 0,
            weightUnit: weightUnit,
            totalDailyInsulinUnits: totalDailyInsulin ?? 0
        )

        isLoading = true
        pumpManager?.configureControlIQMode(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success:
                    self.originalEnabled = self.controlIQEnabled
                    self.originalWeight = self.weight
                    self.originalTDI = self.totalDailyInsulin
                    self.checkDirtyState()
                case let .failure(error):
                    // Report what actually went wrong. Previously every failure read
                    // "check pump connection", which is misleading when the pump
                    // answered and refused the change.
                    self.saveError = error.localizedDescription
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

            self.disabled = !self.isDirty || self.validationError != nil
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
