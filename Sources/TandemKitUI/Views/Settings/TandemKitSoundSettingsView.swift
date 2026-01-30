import LoopKitUI
import SwiftUI
import TandemBLE

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
            return LocalizedString("Beep", comment: "sound setting audioHigh")
        case 3:
            return LocalizedString("Vibrate", comment: "sound setting vibrate")
        default:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            title

            List {
                Section {
                    sectionItem(
                        title: LocalizedString("General (Temp Basal and Bolus)", comment: "Label for general category button sound"),
                        isEditing: isEditingGeneralAnnun,
                        value: $viewModel.generalAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "generalAnnun")
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Quick Bolus", comment: "Label for quick bolus sound"),
                        isEditing: isEditingQuickBolusAnnun,
                        value: $viewModel.quickBolusAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "quickBolusAnnun")
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Reminders", comment: "Label for reminder sound"),
                        isEditing: isEditingReminderAnnun,
                        value: $viewModel.reminderAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "reminderAnnun")
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Alarms", comment: "Label for alarm sound"),
                        isEditing: isEditingAlarmAnnun,
                        value: $viewModel.alarmAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "alarmAnnun")
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Alerts", comment: "Label for alert sound"),
                        isEditing: isEditingAlertAnnun,
                        value: $viewModel.alertAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            toggleEditors(propertyName: "alertAnnun")
                        }
                    }
                }

                Spacer()

                Text(LocalizedString(
                    "Please note that this build of TandemKit does not support silent operation for Temp Basal and Bolus commands on this pump.",
                    comment: "Silent operation limitation notice for TandemKit"
                ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            }

            Spacer()

            ContinueButton(
                text: viewModel
                    .onSubmit == nil ? LocalizedString("Save", comment: "label for save") :
                    LocalizedString("Continue", comment: "continue"),
                loading: $viewModel.isLoading,
                disabled: $viewModel.isDisabled
            ) {
                viewModel.submit()
            }
            .padding(.horizontal)
        }
        .listStyle(InsetGroupedListStyle())
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
        title: String,
        isEditing: Bool,
        value: Binding<Int>
    ) -> some View {
        HStack {
            Text(title)
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

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Sound Settings", comment: "Title for insulin type"))
            .font(.title)
            .bold()
            .padding(.horizontal)

        Text(LocalizedString(
            "You can configure which actions cause your pump to beep or vibrate",
            comment: "Title text for insulin type confirmation page"
        ))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)

        Divider()
            .padding(.vertical)
    }
}
