import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitDeliveryLimitsView: View {
    @ObservedObject var viewModel: TandemKitDeliveryLimitsViewModel
    @State private var isEditingBasal = false
    @State private var isEditingBolus = false
    @State private var showingSaveConfirmation = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Delivery Limits", comment: "Title for delivery limits settings"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            Text(LocalizedString(
                "Set the maximum basal rate and maximum bolus your pump will deliver. These safety limits apply to all profiles.",
                comment: "Description for delivery limits settings"
            ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider()
                .padding(.vertical)

            if viewModel.isFetching {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text(LocalizedString("Loading current limits...", comment: "Loading delivery limits"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    Section(header: Text(LocalizedString(
                        "Max Basal Rate",
                        comment: "Header for max basal rate"
                    ))) {
                        HStack {
                            Text(LocalizedString("Max Basal Rate", comment: "Label for max basal rate"))
                            Spacer()
                            Text(viewModel.maxBasalRateText)
                                .foregroundColor(isEditingBasal ? .accentColor : .secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isEditingBasal.toggle()
                                if isEditingBasal { isEditingBolus = false }
                            }
                        }

                        if isEditingBasal {
                            Picker("", selection: $viewModel.maxBasalRate) {
                                ForEach(Array(stride(from: 0.1, through: 15.0, by: 0.1)), id: \.self) { rate in
                                    Text(String(format: "%.1f U/hr", rate)).tag(rate)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }

                        if let defaultText = viewModel.defaultMaxBasalRateText {
                            Text(defaultText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text(LocalizedString(
                        "Max Bolus",
                        comment: "Header for max bolus"
                    ))) {
                        HStack {
                            Text(LocalizedString("Max Bolus", comment: "Label for max bolus"))
                            Spacer()
                            Text(viewModel.maxBolusText)
                                .foregroundColor(isEditingBolus ? .accentColor : .secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isEditingBolus.toggle()
                                if isEditingBolus { isEditingBasal = false }
                            }
                        }

                        if isEditingBolus {
                            Picker("", selection: $viewModel.maxBolus) {
                                ForEach(Array(stride(from: 0.5, through: 25.0, by: 0.5)), id: \.self) { amount in
                                    Text(String(format: "%.1f U", amount)).tag(amount)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }

                        if let defaultText = viewModel.defaultMaxBolusText {
                            Text(defaultText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if let error = viewModel.saveError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            ContinueButton(
                text: LocalizedString("Save", comment: "label for save"),
                loading: $viewModel.isLoading,
                disabled: Binding(
                    get: { !viewModel.isDirty || viewModel.isFetching },
                    set: { _ in }
                )
            ) {
                showingSaveConfirmation = true
            }
            .padding(.horizontal)
            .actionSheet(isPresented: $showingSaveConfirmation) {
                ActionSheet(
                    title: Text(LocalizedString(
                        "Update Delivery Limits",
                        comment: "Title for delivery limits confirmation"
                    )),
                    message: Text(LocalizedString(
                        "Are you sure you want to update your pump's delivery limits? This affects all insulin delivery profiles.",
                        comment: "Message for delivery limits confirmation"
                    )),
                    buttons: [
                        .default(Text(LocalizedString("Update Limits", comment: "Confirm delivery limits update"))) {
                            viewModel.submit()
                        },
                        .cancel()
                    ]
                )
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}
