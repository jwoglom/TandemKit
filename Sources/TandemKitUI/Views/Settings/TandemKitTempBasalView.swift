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

    /// Redrawn each minute: the effective rates and the accepted percents run from now.
    private var form: some View {
        TimelineView(.everyMinute) { _ in
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
                    }

                    Section(header: SectionHeader(label: String(localized: "Duration", comment: "Header of the temp basal duration section"))) {
                        durationRow
                        if showingDurationPicker {
                            durationPicker
                        }
                    }

                    effectiveBasalRates
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
        switch viewModel.rateView {
        case .percent:
            return String(localized: "of profile basal", comment: "Caption under a temp basal percent")
        case .units:
            return String(
                format: String(
                    localized: "%1$d%% of the %2$@ U/hr profile basal rate",
                    comment: "Caption under a temp basal rate in units per hour (1: the percent, 2: the profile's rate now)"
                ),
                viewModel.percent,
                TandemKitTempBasalViewModel.rateText(viewModel.profileBasalRate)
            )
        }
    }

    /// The selected hours and minutes, each over its own wheel.
    private var durationRow: some View {
        Button(action: {
            isEditingValue = false
            withAnimation { showingDurationPicker.toggle() }
        }) {
            HStack(spacing: 0) {
                Text(Self.hoursText(viewModel.hours))
                    .frame(maxWidth: .infinity)
                Text(Self.minutesText(viewModel.minutes))
                    .frame(maxWidth: .infinity)
            }
            .foregroundColor(viewModel.isDurationValid ? .primary : guidanceColors.critical)
            .overlay(alignment: .trailing) {
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
                    Text(Self.hoursText(hours))
                        .tag(hours)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .clipped()

            Picker(String(localized: "Minutes", comment: "Label of the temp basal minutes wheel"), selection: $viewModel.minutes) {
                ForEach(ManualTempBasalForm.minuteChoices, id: \.self) { minutes in
                    Text(Self.minutesText(minutes))
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

    private static func hoursText(_ hours: Int) -> String {
        String(format: String(localized: "%d hr", comment: "Hours on the temp basal duration row and wheel"), hours)
    }

    private static func minutesText(_ minutes: Int) -> String {
        String(format: String(localized: "%d min", comment: "Minutes on the temp basal duration row and wheel"), minutes)
    }

    @ViewBuilder private var effectiveBasalRates: some View {
        let rates = viewModel.effectiveBasalRates
        if let start = rates.first?.start {
            Section(header: VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.vertical, 12)
                SectionHeader(label: String(localized: "Effective basal rates", comment: "Header of the temp basal screen's list of the rates the temp runs at"))
            }) {
                ForEach(rates, id: \.start) { rate in
                    HStack {
                        Text(effectiveRateSpan(rate, from: start))
                        Spacer()
                        Text(String(
                            format: String(localized: "%@ U/hr", comment: "A rate in units per hour, to two decimals"),
                            TandemKitTempBasalViewModel.rateText(rate.rate)
                        ))
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func effectiveRateSpan(_ rate: ManualTempBasalForm.EffectiveRate, from now: Date) -> String {
        let end = Self.effectiveRateTime(rate.end, now: now)
        guard rate.start > now else {
            return String(
                format: String(localized: "Now – %@", comment: "The temp basal screen's first effective basal rate, from now to a time"),
                end
            )
        }
        return String(
            format: String(
                localized: "%1$@ – %2$@",
                comment: "A later effective basal rate on the temp basal screen (1: its start time, 2: its end time)"
            ),
            Self.effectiveRateTime(rate.start, now: now),
            end
        )
    }

    /// A temp can run 72 hours, so a time past today names its day.
    private static func effectiveRateTime(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? timeFormatter.string(from: date)
            : date.formatted(.dateTime.weekday().hour().minute())
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
