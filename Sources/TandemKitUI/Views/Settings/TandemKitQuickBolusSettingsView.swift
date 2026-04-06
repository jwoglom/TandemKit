import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitQuickBolusSettingsView: View {
    @ObservedObject var viewModel: TandemKitQuickBolusSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Quick Bolus Settings", comment: "Title for quick bolus settings")
                .font(.title)
                .bold()
                .padding(.horizontal)

            Text(
                "Configure the quick bolus button on your pump. Quick bolus lets you deliver insulin or enter carbs using repeated button presses.",
                comment: "Description for quick bolus settings"
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

            Divider()

            List {
                Section {
                    Toggle(isOn: $viewModel.enabled) {
                        Text("Quick Bolus Enabled", comment: "Label for quick bolus enabled toggle")
                    }
                }

                if viewModel.enabled {
                    Section(header: Text("Mode", comment: "Header for quick bolus mode")) {
                        Picker(
                            String(localized: "Entry Type", comment: "Label for quick bolus entry type"),
                            selection: $viewModel.modeIndex
                        ) {
                            Text("Units", comment: "Quick bolus units mode").tag(0)
                            Text("Carbs", comment: "Quick bolus carbs mode").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(header: Text("Increment", comment: "Header for quick bolus increment")) {
                        if viewModel.modeIndex == 0 {
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
                            .frame(height: 120)
                        } else {
                            Picker(
                                String(localized: "Carb Increment", comment: "Label for carb increment picker"),
                                selection: $viewModel.carbsIncrementIndex
                            ) {
                                ForEach(
                                    0 ..< TandemKitQuickBolusSettingsViewModel.carbIncrements.count,
                                    id: \.self
                                ) { index in
                                    Text(TandemKitQuickBolusSettingsViewModel.carbIncrements[index].label)
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
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
