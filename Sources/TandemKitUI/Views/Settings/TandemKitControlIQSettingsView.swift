import LoopKitUI
import SwiftUI

struct TandemKitControlIQSettingsView: View {
    @StateObject var viewModel: TandemKitControlIQSettingsViewModel
    @State private var isEditingWeight = false
    @State private var isEditingTDI = false

    var body: some View {
        VStack(alignment: .leading) {
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

                    if viewModel.controlIQEnabled {
                        sleepScheduleSection
                    }
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
        .alert(item: Binding(
            get: { viewModel.saveError.map { ErrorMessage(message: $0) } },
            set: { _ in viewModel.saveError = nil }
        )) { error in
            Alert(
                title: Text("Error", comment: "Error alert title"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Control-IQ Settings Section

    private var controlIQSection: some View {
        Section(header: Text("Control-IQ", comment: "Header for Control-IQ settings section")) {
            Toggle(
                String(localized: "Enabled", comment: "Control IQ enabled"),
                isOn: $viewModel.controlIQEnabled
            )

            if viewModel.controlIQEnabled {
                // Weight
                HStack {
                    Text("Weight", comment: "Label for weight")
                    Spacer()
                    Text("\(viewModel.weight) lbs")
                        .foregroundColor(isEditingWeight ? .accentColor : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isEditingWeight.toggle()
                        if isEditingWeight { isEditingTDI = false }
                    }
                }

                if isEditingWeight {
                    Picker("", selection: $viewModel.weight) {
                        ForEach(Array(stride(from: 50, through: 400, by: 1)), id: \.self) { lbs in
                            Text("\(lbs) lbs").tag(lbs)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }

                // Total Daily Insulin
                HStack {
                    Text("Total Daily Insulin", comment: "Label for total daily insulin")
                    Spacer()
                    Text("\(viewModel.totalDailyInsulin) U")
                        .foregroundColor(isEditingTDI ? .accentColor : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isEditingTDI.toggle()
                        if isEditingTDI { isEditingWeight = false }
                    }
                }

                if isEditingTDI {
                    Picker("", selection: $viewModel.totalDailyInsulin) {
                        ForEach(Array(stride(from: 1, through: 200, by: 1)), id: \.self) { units in
                            Text("\(units) U").tag(units)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }
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
                ForEach(Array(viewModel.sleepSchedules.enumerated()), id: \.offset) { index, slot in
                    VStack(alignment: .leading, spacing: 4) {
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
                        if slot.enabled {
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
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Helper

private struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
