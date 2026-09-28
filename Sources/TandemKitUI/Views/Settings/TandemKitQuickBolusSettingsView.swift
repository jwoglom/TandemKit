import LoopKitUI
import SwiftUI

struct TandemKitQuickBolusSettingsView: View {
    @ObservedObject var viewModel: TandemKitQuickBolusSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    Toggle(isOn: $viewModel.enabled) {
                        Text("Quick Bolus Enabled", comment: "Label for quick bolus enabled toggle")
                    }
                } footer: {
                    Text(
                        "Configure the quick bolus button on your pump. Quick bolus lets you deliver insulin using repeated button presses.",
                        comment: "Description for quick bolus settings"
                    )
                    .font(.footnote)
                }

                if viewModel.pumpIsInCarbsMode {
                    Section {
                        Text(
                            "Your pump's quick bolus is set to carbs, which this app does not support. In carbs mode the pump doses from its own carb ratio, and the carbs are not shared with this app. Switch it back to units from the pump or the Tandem app, or turn quick bolus off here.",
                            comment: "Warning shown when the pump's quick bolus is in carbs mode"
                        )
                        .font(.footnote)
                        .foregroundColor(.orange)
                    }
                }

                if viewModel.enabled {
                    Section {
                        Picker(
                            String(localized: "Unit Increment", comment: "Label for unit increment picker"),
                            selection: $viewModel.unitsIncrementIndex
                        ) {
                            ForEach(
                                0 ..< TandemKitQuickBolusSettingsViewModel.unitIncrements.count,
                                id: \.self
                            ) { index in
                                Text(TandemKitQuickBolusSettingsViewModel.unitIncrements[index].label)
                                    .tag(index)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 240)
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
                text: Text("Save", comment: "label for save"),
                loading: $viewModel.isLoading,
                disabled: Binding(
                    get: { !viewModel.isDirty },
                    set: { _ in }
                )
            ) {
                viewModel.submit()
            }
            .padding(.horizontal)
        }
        .listStyle(.insetGrouped)
    }
}
