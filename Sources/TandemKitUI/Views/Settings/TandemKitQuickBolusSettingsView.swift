import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitQuickBolusSettingsView: View {
    @ObservedObject var viewModel: TandemKitQuickBolusSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Quick Bolus Settings", comment: "Title for quick bolus settings"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            Text(LocalizedString(
                "Configure the quick bolus button on your pump. Quick bolus lets you deliver insulin or enter carbs using repeated button presses.",
                comment: "Description for quick bolus settings"
            ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider()
                .padding(.vertical)

            List {
                Section {
                    Toggle(isOn: $viewModel.enabled) {
                        Text(LocalizedString("Quick Bolus Enabled", comment: "Label for quick bolus enabled toggle"))
                    }
                }

                if viewModel.enabled {
                    Section(header: Text(LocalizedString("Mode", comment: "Header for quick bolus mode"))) {
                        Picker(
                            LocalizedString("Entry Type", comment: "Label for quick bolus entry type"),
                            selection: $viewModel.modeIndex
                        ) {
                            Text(LocalizedString("Units", comment: "Quick bolus units mode")).tag(0)
                            Text(LocalizedString("Carbs", comment: "Quick bolus carbs mode")).tag(1)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(header: Text(LocalizedString("Increment", comment: "Header for quick bolus increment"))) {
                        if viewModel.modeIndex == 0 {
                            Picker(
                                LocalizedString("Unit Increment", comment: "Label for unit increment picker"),
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
                                LocalizedString("Carb Increment", comment: "Label for carb increment picker"),
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
                text: LocalizedString("Save", comment: "label for save"),
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
        .listStyle(InsetGroupedListStyle())
    }
}
