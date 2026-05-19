import LoopKitUI
import SwiftUI

struct TandemKitSoundSettingsView: View {
    @ObservedObject var viewModel: TandemKitSoundSettingsViewModel

    @State var isEditingGeneralAnnun: Bool = false
    @State var isEditingQuickBolusAnnun: Bool = false
    @State var isEditingReminderAnnun: Bool = false
    @State var isEditingAlarmAnnun: Bool = false
    @State var isEditingAlertAnnun: Bool = false

    private let soundValueRange = [0, 3]
    private func soundSettingFormatter(_ value: Int) -> String {
        switch value {
        case 0:
            return String(localized: "Beep", comment: "sound setting audioHigh")
        case 3:
            return String(localized: "Vibrate", comment: "sound setting vibrate")
        default:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    sectionItem(
                        title: Text(
                            "General (Temp Basal and Bolus)",
                            comment: "Label for general category button sound"
                        ),
                        isEditing: isEditingGeneralAnnun,
                        value: $viewModel.generalAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "generalAnnun")
                        }
                    }

                    sectionItem(
                        title: Text("Quick Bolus", comment: "Label for quick bolus sound"),
                        isEditing: isEditingQuickBolusAnnun,
                        value: $viewModel.quickBolusAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "quickBolusAnnun")
                        }
                    }

                    sectionItem(
                        title: Text("Reminders", comment: "Label for reminder sound"),
                        isEditing: isEditingReminderAnnun,
                        value: $viewModel.reminderAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "reminderAnnun")
                        }
                    }

                    sectionItem(
                        title: Text("Alarms", comment: "Label for alarm sound"),
                        isEditing: isEditingAlarmAnnun,
                        value: $viewModel.alarmAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "alarmAnnun")
                        }
                    }

                    sectionItem(
                        title: Text("Alerts", comment: "Label for alert sound"),
                        isEditing: isEditingAlertAnnun,
                        value: $viewModel.alertAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "alertAnnun")
                        }
                    }
                } footer: {
                    Text(
                        "You can configure which actions cause your pump to beep or vibrate",
                        comment: "Title text for insulin type confirmation page"
                    )
                    .font(.footnote)
                }
            }

            Spacer()

            Text(
                "This build of TandemKit does not support silent operation for Temp Basal and Bolus commands on this pump.",
                comment: "Silent operation limitation notice for TandemKit"
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

            Spacer()

            ContinueButton(
                text: viewModel
                    .onSubmit == nil ? Text("Save", comment: "label for save") :
                    Text("Continue", comment: "continue"),
                loading: $viewModel.isLoading,
                disabled: $viewModel.isDisabled
            ) {
                viewModel.submit()
            }
            .padding(.horizontal)
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(String(localized: "Sound Settings", comment: "Title for insulin type"))
    }

    func toggleEditors(propertyName: String) {
        if propertyName == "generalAnnun" {
            isEditingGeneralAnnun.toggle()
        } else {
            isEditingGeneralAnnun = false
        }

        if propertyName == "quickBolusAnnun" {
            isEditingQuickBolusAnnun.toggle()
        } else {
            isEditingQuickBolusAnnun = false
        }

        if propertyName == "reminderAnnun" {
            isEditingReminderAnnun.toggle()
        } else {
            isEditingReminderAnnun = false
        }

        if propertyName == "alarmAnnun" {
            isEditingAlarmAnnun.toggle()
        } else {
            isEditingAlarmAnnun = false
        }

        if propertyName == "alertAnnun" {
            isEditingAlertAnnun.toggle()
        } else {
            isEditingAlertAnnun = false
        }
    }

    @ViewBuilder func sectionItem(
        title: Text,
        isEditing: Bool,
        value: Binding<Int>
    ) -> some View {
        HStack {
            title
            Spacer()
            Text(soundSettingFormatter(value.wrappedValue))
        }
        .foregroundColor(isEditing ? Color.accentColor : Color.primary)

        if isEditing {
            ResizeablePicker(
                selection: value,
                data: soundValueRange,
                formatter: { value in soundSettingFormatter(value) }
            )
            .padding(.horizontal)
        }
    }
}
