import LoopKitUI
import SwiftUI

struct TandemKitControlIQSettingsView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitControlIQSettingsViewModel
    @State private var isEditingWeight = false
    @State private var isEditingTDI = false
    @State private var editingSlot: Int?

    /// Sleep schedule times are a minute count on the wire; offered in five-minute steps, which is
    /// the granularity the pump's own screens use.
    private static let timeStepMinutes = 5

    /// The grid, plus 23:59, which Tandem's app ends an all-day schedule at, and the slot's own time,
    /// so a time off the grid stays selected rather than leaving the picker blank.
    private static func timeOptions(including current: Int) -> [Int] {
        let grid = stride(from: 0, to: 24 * 60, by: timeStepMinutes)
        return Set(grid).union([24 * 60 - 1, current]).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeAlgorithmOnlyWarningCard
                .padding([.horizontal, .top])

            if viewModel.isFetching {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text("Loading settings...", comment: "Loading Control-IQ settings")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    controlIQSection
                    sleepScheduleSection
                }
                .listStyle(InsetGroupedListStyle())

                Spacer()

                ContinueButton(
                    text: Text("Save", comment: "Save action"),
                    loading: $viewModel.isLoading,
                    disabled: $viewModel.disabled,
                ) {
                    viewModel.saveControlIQSettings()
                }
                .padding(.horizontal)
            }
        }
        .alert(item: activeAlert) { alert in
            switch alert {
            case let .error(message):
                return Alert(
                    title: Text("Error", comment: "Error alert title"),
                    message: Text(message),
                    dismissButton: .default(Text("OK", comment: "Button to dismiss an error alert"))
                )
            case let .enable(prompt):
                return prompt.alert(
                    confirm: { viewModel.confirmEnablingControlIQ() },
                    openCgmSettings: { viewModel.openCgmSettings() },
                    openControlIQSettings: {}
                )
            }
        }
    }

    private var activeAlert: Binding<ControlIQSettingsAlert?> {
        Binding(
            get: {
                if let prompt = viewModel.enablePrompt {
                    return .enable(prompt)
                }
                return viewModel.saveError.map { .error($0) }
            },
            set: { _ in
                viewModel.enablePrompt = nil
                viewModel.saveError = nil
            }
        )
    }

    private var nativeAlgorithmOnlyWarningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(guidanceColors.warning)
                .font(.title2)
            Text(String(
                format: String(
                    localized: "These options are only used when the pump's native Control-IQ algorithm is enabled, and separate from %@'s Closed Loop settings.",
                    comment: "Warning at the top of the Control-IQ settings screen, parameter is app name"
                ),
                HostApp.current.appName
            ))
            .font(.subheadline)
        }
        .wizardCard(background: guidanceColors.warning.opacity(0.1))
    }

    // MARK: - Control-IQ Settings Section

    /// Weight and total daily insulin are shown whether or not Control-IQ is on: they have to be
    /// entered before it can be turned on, and a pump that has never run Control-IQ reports neither,
    /// so gating them behind the toggle left no way to supply them (#223).
    private var controlIQSection: some View {
        Section(
            header: Text("Control-IQ", comment: "Header for Control-IQ settings section"),
            footer: Text(
                "Control-IQ uses your weight and total daily insulin to dose. Your care team can help you confirm these values.",
                comment: "Footer explaining what the Control-IQ values are used for"
            )
        ) {
            Toggle(
                String(localized: "Enabled", comment: "Control IQ enabled"),
                isOn: $viewModel.controlIQEnabled
            )

            weightRow

            if isEditingWeight {
                Picker("", selection: Binding(
                    get: { viewModel.weightLbs ?? TandemKitControlIQSettingsViewModel.weightSeedLbs },
                    set: { viewModel.weightLbs = $0 }
                )) {
                    ForEach(
                        Array(stride(
                            from: ControlIQSettingsLimits.allowedWeightLbs.lowerBound,
                            through: 400,
                            by: 1
                        )),
                        id: \.self
                    ) { lbs in
                        Text("\(lbs) lbs", comment: "Control-IQ weight picker option, in pounds").tag(lbs)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }

            totalDailyInsulinRow

            if isEditingTDI {
                Picker("", selection: Binding(
                    get: {
                        viewModel.totalDailyInsulin
                            ?? TandemKitControlIQSettingsViewModel.totalDailyInsulinSeedUnits
                    },
                    set: { viewModel.totalDailyInsulin = $0 }
                )) {
                    ForEach(
                        Array(stride(
                            from: ControlIQSettingsLimits.allowedTotalDailyInsulinUnits.lowerBound,
                            through: 200,
                            by: 1
                        )),
                        id: \.self
                    ) { units in
                        Text("\(units) U", comment: "Control-IQ total daily insulin picker option, in insulin units").tag(units)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }

            if let validationMessage = viewModel.validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundColor(guidanceColors.warning)
            }
        }
    }

    private var weightRow: some View {
        HStack {
            Text("Weight", comment: "Label for weight")
            Spacer()
            if let weightLbs = viewModel.weightLbs {
                Text("\(weightLbs) lbs", comment: "Control-IQ weight, in pounds")
                    .foregroundColor(isEditingWeight ? .accentColor : .secondary)
            } else {
                Text("Not set", comment: "Shown when a Control-IQ value has never been configured")
                    .foregroundColor(isEditingWeight ? .accentColor : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isEditingWeight.toggle()
                if isEditingWeight { isEditingTDI = false }
            }
        }
    }

    private var totalDailyInsulinRow: some View {
        HStack {
            Text("Total Daily Insulin", comment: "Label for total daily insulin")
            Spacer()
            if let totalDailyInsulin = viewModel.totalDailyInsulin {
                Text("\(totalDailyInsulin) U", comment: "Control-IQ total daily insulin, in insulin units")
                    .foregroundColor(isEditingTDI ? .accentColor : .secondary)
            } else {
                Text("Not set", comment: "Shown when a Control-IQ value has never been configured")
                    .foregroundColor(isEditingTDI ? .accentColor : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isEditingTDI.toggle()
                if isEditingTDI { isEditingWeight = false }
            }
        }
    }

    // MARK: - Sleep Schedule Section

    private var sleepScheduleSection: some View {
        Section(header: Text("Sleep Schedules", comment: "Header for sleep schedule section")) {
            if viewModel.sleepSchedules.isEmpty {
                Text("No sleep schedules available", comment: "Text when no sleep schedules")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(viewModel.sleepSchedules.indices), id: \.self) { index in
                    sleepScheduleRow(index: index)
                }

                if !viewModel.canEditSleepSchedules {
                    Text(
                        "Sleep schedules can only be changed on the pump itself, or in the Tandem app.",
                        comment: "Note shown when the pump does not accept sleep schedule changes"
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func sleepScheduleRow(index: Int) -> some View {
        let slot = viewModel.sleepSchedules[index]
        let isEditing = editingSlot == index

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "Schedule", comment: "Sleep schedule label") + " \(index + 1)")
                    .fontWeight(.medium)
                Spacer()
                Text(
                    slot.enabled
                        ? String(localized: "Enabled", comment: "Sleep schedule enabled")
                        : String(localized: "Disabled", comment: "Sleep schedule disabled")
                )
                .foregroundColor(slot.enabled ? .green : .secondary)
                .font(.caption)
            }
            // Only the header opens the editor, so the gesture does not compete with the controls
            // inside the row.
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.canEditSleepSchedules else { return }
                withAnimation {
                    editingSlot = isEditing ? nil : index
                }
            }

            if slot.enabled, !isEditing {
                HStack {
                    Text("\(slot.startTimeText) – \(slot.endTimeText)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(slot.activeDaysText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if isEditing {
                sleepScheduleEditor(index: index, slot: slot)
            }
        }
        .padding(.vertical, 2)
    }

    private func sleepScheduleEditor(index: Int, slot: SleepScheduleSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                String(localized: "Use this schedule", comment: "Toggle to enable a sleep schedule"),
                isOn: binding(index: index, current: slot.enabled) { $0.enabled = $1 }
            )

            HStack(spacing: 6) {
                ForEach(0 ..< 7, id: \.self) { day in
                    dayToggle(index: index, slot: slot, day: day)
                }
            }

            timeRow(
                label: Text("Start", comment: "Sleep schedule start time label"),
                minutes: binding(index: index, current: slot.startTime) { $0.startTime = $1 }
            )
            timeRow(
                label: Text("End", comment: "Sleep schedule end time label"),
                minutes: binding(index: index, current: slot.endTime) { $0.endTime = $1 }
            )

            ContinueButton(
                text: Text("Save Schedule", comment: "Save a single sleep schedule"),
                loading: $viewModel.isLoading,
                disabled: .constant(!viewModel.isSleepScheduleDirty(index)),
                buttonStyle: .secondary
            ) {
                viewModel.saveSleepSchedule(slot: index)
            }
        }
    }

    /// A binding onto one field of one slot. Reads use the value the row rendered with and writes
    /// are bounds-checked, so a binding left over from a re-fetch that replaced the schedules cannot
    /// index past the end of the array.
    private func binding<T>(
        index: Int,
        current: T,
        set: @escaping (inout SleepScheduleSlot, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { current },
            set: { newValue in
                guard viewModel.sleepSchedules.indices.contains(index) else { return }
                var slot = viewModel.sleepSchedules[index]
                set(&slot, newValue)
                viewModel.sleepSchedules[index] = slot
            }
        )
    }

    private func dayToggle(index: Int, slot: SleepScheduleSlot, day: Int) -> some View {
        let isActive = slot.isActive(day: day)

        return Button {
            guard viewModel.sleepSchedules.indices.contains(index) else { return }
            var updated = viewModel.sleepSchedules[index]
            updated.setActive(day: day, !isActive)
            viewModel.sleepSchedules[index] = updated
        } label: {
            Text(SleepScheduleSlot.dayLetters[day])
                .font(.caption)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor : Color.clear)
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SleepScheduleSlot.dayLetters[day])
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func timeRow(label: Text, minutes: Binding<Int>) -> some View {
        HStack {
            label
            Spacer()
            Picker("", selection: minutes) {
                ForEach(Self.timeOptions(including: minutes.wrappedValue), id: \.self) { minute in
                    Text(SleepScheduleSlot.formatMinutes(minute)).tag(minute)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Helper

/// Save's error and the prompts of a Save that turns Control-IQ on share the view's one alert.
private enum ControlIQSettingsAlert: Identifiable {
    case error(String)
    case enable(ControlIQEnablePrompt)

    var id: String {
        switch self {
        case let .error(message):
            return "error:\(message)"
        case let .enable(prompt):
            return prompt.id
        }
    }
}
