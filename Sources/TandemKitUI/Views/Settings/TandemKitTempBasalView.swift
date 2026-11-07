import LoopKitUI
import SwiftUI

struct TandemKitTempBasalView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @ObservedObject var viewModel: TandemKitTempBasalViewModel

    @State private var showingDurationPicker = false
    @State private var editedValue = ""
    @FocusState private var isEditingValue: Bool

    private typealias RateView = TandemKitTempBasalViewModel.RateView

    var body: some View {
        content
            .onAppear { viewModel.load() }
            .sheet(item: $viewModel.failure) { failure in
                ErrorSheetView(content: failure, tint: guidanceColors.critical)
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.screen {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unreachable:
            unreachable
        case .suspended:
            notice(String(
                localized: "Insulin delivery is suspended. Resume delivery before setting a temp basal.",
                comment: "Temp basal screen while the pump is suspended"
            ))
        case .form:
            form
        case let .active(status):
            active(status)
        }
    }

    // MARK: - States without a form

    private var unreachable: some View {
        VStack(spacing: 20) {
            notice(String(
                localized: "Could not read the pump's temp rate. Keep the pump near your phone and try again.",
                comment: "Temp basal screen when the pump did not answer"
            ))
            ContinueButton(text: Text("Retry", comment: "Button to read the pump's temp rate again")) {
                viewModel.load()
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
    }

    // MARK: - Set

    private var form: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Picker(String(localized: "Rate", comment: "Label of the temp basal rate kind picker"), selection: $viewModel.rateView) {
                        Text("Percent rate", comment: "Temp basal screen tab for a rate as a percent of the profile")
                            .tag(RateView.percent)
                        Text("Unit rate", comment: "Temp basal screen tab for a rate in units per hour")
                            .tag(RateView.units)
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isSending)
                }

                Section(header: SectionHeader(label: String(localized: "Rate", comment: "Header of the temp basal rate section"))) {
                    rateControl
                    if let change = viewModel.profileChange {
                        profileChangeNote(change)
                    }
                }

                Section(header: SectionHeader(label: String(localized: "Duration", comment: "Header of the temp basal duration section"))) {
                    durationRow
                    if showingDurationPicker {
                        durationPicker
                    }
                }
            }
            .listStyle(.insetGrouped)

            ContinueButton(
                text: Text("Set temp rate", comment: "Button to set a temp basal from the temp basal screen"),
                loading: Binding(get: { viewModel.isSending }, set: { _ in }),
                disabled: Binding(get: { !viewModel.canSet }, set: { _ in })
            ) {
                isEditingValue = false
                viewModel.showingSetConfirmation = true
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done", comment: "Button that ends typing a temp basal rate")) {
                    isEditingValue = false
                }
            }
        }
        .alert(isPresented: $viewModel.showingSetConfirmation) {
            Alert(
                title: Text(viewModel.setConfirmationMessage),
                primaryButton: .default(Text("Set temp rate", comment: "Button that confirms setting a temp basal")) {
                    viewModel.set()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var rateControl: some View {
        VStack(spacing: 8) {
            HStack {
                stepButton(systemName: "minus.circle.fill", enabled: viewModel.canStepDown) { viewModel.stepDown() }
                Spacer()
                valueField
                Spacer()
                stepButton(systemName: "plus.circle.fill", enabled: viewModel.canStepUp) { viewModel.stepUp() }
            }
            Text(rateCaption)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            isEditingValue = false
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 34))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }

    private var valueField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("", text: $editedValue)
                .keyboardType(viewModel.rateView == .percent ? .numberPad : .decimalPad)
                .focused($isEditingValue)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(viewModel.isPercentValid ? .primary : guidanceColors.critical)
                .frame(minWidth: 70, maxWidth: 130)
                .disabled(viewModel.isSending)
            Text(viewModel.rateView == .percent ? "%" : String(localized: "U/hr", comment: "Units per hour after a temp basal rate"))
                .foregroundColor(.secondary)
        }
        .onAppear { editedValue = displayedValue }
        .onChange(of: viewModel.percent) { _ in
            if !isEditingValue { editedValue = displayedValue }
        }
        .onChange(of: viewModel.rateView) { _ in
            isEditingValue = false
            editedValue = displayedValue
        }
        .onChange(of: viewModel.profileBasalRate) { _ in
            if !isEditingValue { editedValue = displayedValue }
        }
        .onChange(of: isEditingValue) { editing in
            if !editing { commitEditedValue() }
        }
    }

    private var displayedValue: String {
        switch viewModel.rateView {
        case .percent:
            return "\(viewModel.percent)"
        case .units:
            return TandemKitTempBasalViewModel.rateText(viewModel.rate)
        }
    }

    /// A typed value is kept as typed, valid or not: the screen never picks another number for the user.
    private func commitEditedValue() {
        let text = editedValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        switch viewModel.rateView {
        case .percent:
            if let typed = Int(text) { viewModel.percent = typed }
        case .units:
            if let typed = Double(text) { viewModel.setRate(typed) }
        }
        editedValue = displayedValue
    }

    private var rateCaption: String {
        let profile = TandemKitTempBasalViewModel.rateText(viewModel.profileBasalRate)
        switch viewModel.rateView {
        case .percent:
            return String(
                format: String(
                    localized: "of the profile basal rate (currently %@ U/hr)",
                    comment: "Caption under a temp basal percent (the profile's rate now)"
                ),
                profile
            )
        case .units:
            return String(
                format: String(
                    localized: "%1$d%% of the %2$@ U/hr profile basal rate",
                    comment: "Caption under a temp basal rate in units per hour (1: the percent, 2: the profile's rate now)"
                ),
                viewModel.percent,
                profile
            )
        }
    }

    private func profileChangeNote(_ change: TandemKitTempBasalViewModel.ProfileChange) -> some View {
        var text = String(
            format: String(
                localized: "At %1$@ your profile changes to %2$@ U/hr, and this temp rate will run at %3$@ U/hr (%4$d%%).",
                comment: "Note on the temp basal screen when a profile segment change falls inside the duration (1: time, 2: new profile rate, 3: new temp rate, 4: percent)"
            ),
            Self.timeFormatter.string(from: change.date),
            TandemKitTempBasalViewModel.rateText(change.profileRate),
            TandemKitTempBasalViewModel.rateText(change.tempRate),
            viewModel.percent
        )
        if change.laterChanges > 0 {
            text += " " + String(
                format: String(
                    localized: "The profile changes %d more times during it.",
                    comment: "Added to the profile change note when more segment changes fall inside the temp basal's duration (the count)"
                ),
                change.laterChanges
            )
        }
        return Label {
            Text(text)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var durationRow: some View {
        Button(action: {
            isEditingValue = false
            withAnimation { showingDurationPicker.toggle() }
        }) {
            HStack {
                Text("Duration", comment: "Label of the temp basal duration row")
                    .foregroundColor(.primary)
                Spacer()
                Text(viewModel.collapsedDurationText)
                    .foregroundColor(viewModel.isDurationValid ? .secondary : guidanceColors.critical)
                Image(systemName: showingDurationPicker ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            Picker(String(localized: "Hours", comment: "Label of the temp basal hours wheel"), selection: $viewModel.hours) {
                ForEach(ManualTempBasalForm.hourChoices, id: \.self) { hours in
                    Text(String(format: String(localized: "%d hr", comment: "Hours on the temp basal duration wheel"), hours))
                        .tag(hours)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .clipped()

            Picker(String(localized: "Minutes", comment: "Label of the temp basal minutes wheel"), selection: $viewModel.minutes) {
                ForEach(ManualTempBasalForm.minuteChoices, id: \.self) { minutes in
                    Text(String(format: String(localized: "%d min", comment: "Minutes on the temp basal duration wheel"), minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 160)
    }

    // MARK: - Active

    private func active(_ status: TempRateStatus) -> some View {
        let percent = status.percent ?? 0
        return VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text(verbatim: "\(percent)%")
                            .font(.system(size: 44, weight: .semibold))
                        Text(String(
                            format: String(localized: "%@ U/hr right now", comment: "The rate a running temp basal delivers now"),
                            TandemKitTempBasalViewModel.rateText(status.currentBasalRate)
                        ))
                        Text(String(
                            format: String(
                                localized: "(%1$d%% of the %2$@ U/hr profile)",
                                comment: "A running temp basal's percent of the profile rate (1: percent, 2: profile rate)"
                            ),
                            percent,
                            TandemKitTempBasalViewModel.rateText(status.profileBasalRate)
                        ))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    HStack {
                        Text("Remaining", comment: "Label of a running temp basal's time left")
                        Spacer()
                        TimelineView(.everyMinute) { context in
                            Text(Self.remainingText(until: status.endDate, now: context.date))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            ContinueButton(
                text: Text("Stop temp rate", comment: "Button to stop the running temp basal"),
                loading: Binding(get: { viewModel.isSending }, set: { _ in }),
                buttonStyle: .destructive
            ) {
                viewModel.showingStopConfirmation = true
            }
            .padding()
        }
        .alert(isPresented: $viewModel.showingStopConfirmation) {
            Alert(
                title: Text(viewModel.stopConfirmationMessage(percent: percent)),
                primaryButton: .destructive(Text("Stop temp rate", comment: "Button that confirms stopping the running temp basal")) {
                    viewModel.stop()
                },
                secondaryButton: .cancel()
            )
        }
    }

    /// Rounded up, so a temp with seconds left still reads "1 min".
    static func remainingText(until end: Date?, now: Date) -> String {
        guard let end else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.hour, .minute]
        let minutes = (max(0, end.timeIntervalSince(now)) / 60).rounded(.up)
        return formatter.string(from: minutes * 60) ?? ""
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
