import Combine
import Foundation
import LoopKit

class TandemKitControlIQSettingsViewModel: ObservableObject {
    /// Values the pickers scroll from when the pump has none configured. `weightLbs` and
    /// `totalDailyInsulin` stay nil until the user picks a value, so a seed is never saved as if the
    /// user had entered it.
    static let weightSeedLbs = 150
    static let totalDailyInsulinSeedUnits = 30

    @Published var controlIQEnabled = false { didSet { recomputeSaveState() } }
    /// nil until Control-IQ has been configured on the pump, or the user picks a value.
    @Published var weightLbs: Int? { didSet { recomputeSaveState() } }
    /// nil until Control-IQ has been configured on the pump, or the user picks a value.
    @Published var totalDailyInsulin: Int? { didSet { recomputeSaveState() } }

    @Published var sleepSchedules: [SleepScheduleSlot] = []
    /// False when the pump cannot accept sleep schedule writes, in which case they are shown but not
    /// editable.
    @Published var canEditSleepSchedules: Bool = false

    @Published var isFetching: Bool = true
    @Published var isDirty: Bool = false
    @Published var disabled: Bool = true
    @Published var isLoading: Bool = false
    @Published var saveError: String?
    /// Why saving is blocked, shown inline under the fields. nil when it is not.
    @Published var validationMessage: String?

    private var originalEnabled: Bool = false
    private var originalWeightLbs: Int?
    private var originalTDI: Int?
    private var originalSleepSchedules: [SleepScheduleSlot] = []

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        if let state = pumpManager?.state {
            controlIQEnabled = state.useControlIQ
            originalEnabled = state.useControlIQ
            weightLbs = state.controlIQWeightLbs
            originalWeightLbs = state.controlIQWeightLbs
            totalDailyInsulin = state.controlIQTotalDailyInsulin
            originalTDI = state.controlIQTotalDailyInsulin
        }
        canEditSleepSchedules = pumpManager?.supports(SetSleepScheduleRequest.self) ?? false

        recomputeSaveState()
        fetchCurrentSettings()
    }

    // MARK: - Fetch

    func fetchCurrentSettings() {
        isFetching = true

        pumpManager?.getControlIQData { ciqResponse, scheduleResponse in
            DispatchQueue.main.async {
                if let ciqResponse {
                    // The pump reports the weight in whichever unit it displays; the request
                    // always carries pounds, so normalize before it reaches the picker. Zero means
                    // Control-IQ has never been configured on this pump.
                    let reportedWeight = ControlIQSettingsLimits.pounds(
                        from: ciqResponse.getWeight(),
                        unit: ciqResponse.weightUnit
                    )
                    let reportedTDI = ciqResponse.getTotalDailyInsulin()

                    self.controlIQEnabled = ciqResponse.getClosedLoopEnabled()
                    self.originalEnabled = ciqResponse.getClosedLoopEnabled()
                    self.weightLbs = reportedWeight == 0 ? nil : reportedWeight
                    self.originalWeightLbs = self.weightLbs
                    self.totalDailyInsulin = reportedTDI == 0 ? nil : reportedTDI
                    self.originalTDI = self.totalDailyInsulin
                }

                if let scheduleResponse {
                    self.showSleepSchedules(scheduleResponse)
                }

                self.isFetching = false
                self.recomputeSaveState()
            }
        }
    }

    // MARK: - Save ControlIQ Settings

    func saveControlIQSettings() {
        saveError = nil

        // The Save button is already disabled in this state, and the driver refuses the request
        // anyway. Checked here so a programmatic call cannot skip both.
        if controlIQEnabled, weightLbs == nil || totalDailyInsulin == nil {
            recomputeSaveState()
            return
        }

        isLoading = true

        var changedFields: ControlIQSettingsFields = []
        if controlIQEnabled != originalEnabled {
            changedFields.insert(.enabled)
        }
        if weightLbs != originalWeightLbs {
            changedFields.insert(.weight)
        }
        if totalDailyInsulin != originalTDI {
            changedFields.insert(.totalDailyInsulin)
        }

        let request = ChangeControlIQSettingsRequest(
            enabled: controlIQEnabled,
            weightLbs: weightLbs ?? 0,
            totalDailyInsulinUnits: totalDailyInsulin ?? 0,
            changedFields: changedFields
        )

        pumpManager?.configureControlIQMode(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success:
                    self.originalEnabled = self.controlIQEnabled
                    self.originalWeightLbs = self.weightLbs
                    self.originalTDI = self.totalDailyInsulin
                    self.recomputeSaveState()
                case let .failure(error):
                    self.saveError = Self.message(for: error)
                }
            }
        }
    }

    // MARK: - Save Sleep Schedule

    /// Whether slot `index` differs from what the pump reported, i.e. whether there is anything to
    /// save.
    func isSleepScheduleDirty(_ index: Int) -> Bool {
        guard index >= 0, index < sleepSchedules.count, index < originalSleepSchedules.count else {
            return false
        }
        return sleepSchedules[index] != originalSleepSchedules[index]
    }

    func saveSleepSchedule(slot: Int) {
        guard slot >= 0, slot < sleepSchedules.count else { return }
        saveError = nil
        isLoading = true

        let schedule = sleepSchedules[slot].toProtocol()
        pumpManager?.setSleepSchedule(slot: slot, schedule: schedule) { error, readBack in
            DispatchQueue.main.async {
                self.isLoading = false
                if slot < self.sleepSchedules.count, slot < self.originalSleepSchedules.count {
                    if let held = readBack?.schedule(at: slot) {
                        self.sleepSchedules[slot] = SleepScheduleSlot(from: held, index: slot)
                        self.originalSleepSchedules[slot] = self.sleepSchedules[slot]
                    } else if error == nil {
                        self.originalSleepSchedules[slot] = self.sleepSchedules[slot]
                    }
                }
                if let error {
                    self.saveError = Self.message(for: error)
                }
            }
        }
    }

    private func showSleepSchedules(_ response: ControlIQSleepScheduleResponse) {
        sleepSchedules = response.schedules.enumerated().map { SleepScheduleSlot(from: $0.element, index: $0.offset) }
        originalSleepSchedules = sleepSchedules
    }

    // MARK: - Helpers

    static func message(for error: Error) -> String {
        [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func recomputeSaveState() {
        let message = Self.validationMessage(
            enabled: controlIQEnabled,
            weightLbs: weightLbs,
            totalDailyInsulin: totalDailyInsulin
        )
        let dirty = controlIQEnabled != originalEnabled
            || weightLbs != originalWeightLbs
            || totalDailyInsulin != originalTDI

        // Deferred to the next main-queue turn: `didSet` can fire while the view is reading these
        // properties, and publishing from inside a view update is not allowed. Ordering is FIFO, so
        // the last recompute wins.
        DispatchQueue.main.async { self.apply(validationMessage: message, isDirty: dirty) }
    }

    private func apply(validationMessage message: String?, isDirty dirty: Bool) {
        validationMessage = message
        isDirty = dirty
        disabled = !dirty || message != nil
    }

    /// Why the settings cannot be saved as they stand.
    ///
    /// Control-IQ doses from body weight and total daily insulin, and a pump that has never had them
    /// set reports neither, so both have to be entered before it can be turned on. Sending the
    /// reported zeroes instead is what produced a bare "Failed to update Control-IQ settings"
    /// (#223).
    static func validationMessage(enabled: Bool, weightLbs: Int?, totalDailyInsulin: Int?) -> String? {
        guard enabled else { return nil }

        switch (weightLbs, totalDailyInsulin) {
        case (nil, nil):
            return String(
                localized: "Enter your weight and total daily insulin to turn on Control-IQ.",
                comment: "Blocking message when both Control-IQ values are missing"
            )
        case (nil, _):
            return String(
                localized: "Enter your weight to turn on Control-IQ.",
                comment: "Blocking message when the Control-IQ weight is missing"
            )
        case (_, nil):
            return String(
                localized: "Enter your total daily insulin to turn on Control-IQ.",
                comment: "Blocking message when the Control-IQ total daily insulin is missing"
            )
        default:
            break
        }

        switch ControlIQSettingsLimits.validate(
            weightLbs: weightLbs ?? 0,
            totalDailyInsulinUnits: totalDailyInsulin ?? 0
        ) {
        case .totalDailyInsulinOutOfRange:
            return String(
                format: String(
                    localized: "Control-IQ needs a total daily insulin of at least %@ units.",
                    comment: "Blocking message when the Control-IQ total daily insulin is too low"
                ),
                String(ControlIQSettingsLimits.allowedTotalDailyInsulinUnits.lowerBound)
            )
        case .weightOutOfRange:
            return String(
                localized: "Enter your weight to turn on Control-IQ.",
                comment: "Blocking message when the Control-IQ weight is missing"
            )
        case nil:
            return nil
        }
    }
}

// MARK: - Sleep Schedule Model

struct SleepScheduleSlot: Identifiable, Equatable {
    let id: Int
    var enabled: Bool
    var activeDays: Int
    var startTime: Int // minutes from midnight
    var endTime: Int // minutes from midnight

    init(from schedule: ControlIQSleepScheduleResponse.SleepSchedule, index: Int) {
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
        SleepScheduleSlot.formatMinutes(startTime)
    }

    var endTimeText: String {
        SleepScheduleSlot.formatMinutes(endTime)
    }

    static func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    /// Day-of-week letters in the order of the pump's `activeDays` bitmask (`MultiDay`), bit 0 being
    /// Monday. `veryShortWeekdaySymbols` starts on Sunday.
    static let dayLetters: [String] = {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return Array(symbols.dropFirst()) + symbols.prefix(1)
    }()

    func isActive(day: Int) -> Bool {
        activeDays & (1 << day) != 0
    }

    mutating func setActive(day: Int, _ active: Bool) {
        if active {
            activeDays |= (1 << day)
        } else {
            activeDays &= ~(1 << day)
        }
    }

    var activeDaysText: String {
        let result = (0 ..< 7).filter { isActive(day: $0) }.map { SleepScheduleSlot.dayLetters[$0] }
        return result.isEmpty
            ? String(localized: "None", comment: "Shown when a sleep schedule has no active days")
            : result.joined(separator: " ")
    }
}
