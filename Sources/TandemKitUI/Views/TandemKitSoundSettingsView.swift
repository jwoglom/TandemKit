import LoopKitUI
import SwiftUI
import TandemBLE

struct TandemKitSoundSettingsView: View {
    @ObservedObject var viewModel: TandemKitSoundSettingsViewModel

    @State var isEditingButtonAnnun: Bool = false
    @State var isEditingQuickBolusAnnun: Bool = false
    @State var isEditingBolusAnnun: Bool = false
    @State var isEditingReminderAnnun: Bool = false
    @State var isEditingAlarmAnnun: Bool = false
    @State var isEditingAlertAnnun: Bool = false
    @State var isEditingFillingTubeAnnun: Bool = false

    private let soundValueRange = Array(0 ... 3)
    private func soundSettingFormatter(_ value: Int) -> String {
        switch value {
        case 0:
            return LocalizedString("Audio high", comment: "sound setting audioHigh")
        case 1:
            return LocalizedString("Audio medium", comment: "sound setting audioMedium")
        case 2:
            return LocalizedString("Audio low", comment: "sound setting audioLow")
        case 3:
            return LocalizedString("Vibrate", comment: "sound setting vibrate")
        default:
            return ""
        }
    }

    var body: some View {
        VStack {
            List {
                Section {
                    sectionItem(
                        title: LocalizedString("Button sound", comment: "Label for button sound"),
                        isEditing: isEditingButtonAnnun,
                        value: $viewModel.buttonAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun.toggle()
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Quick bolus sound", comment: "Label for quick bolus sound"),
                        isEditing: isEditingQuickBolusAnnun,
                        value: $viewModel.quickBolusAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun.toggle()
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Bolus sound", comment: "Label for bolus sound"),
                        isEditing: isEditingBolusAnnun,
                        value: $viewModel.bolusAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun.toggle()
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Reminder sound", comment: "Label for reminder sound"),
                        isEditing: isEditingReminderAnnun,
                        value: $viewModel.reminderAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun.toggle()
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Alarm sound", comment: "Label for alarm sound"),
                        isEditing: isEditingAlarmAnnun,
                        value: $viewModel.alarmAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun.toggle()
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Alert sound", comment: "Label for alert sound"),
                        isEditing: isEditingAlertAnnun,
                        value: $viewModel.alertAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun.toggle()
                            self.isEditingFillingTubeAnnun = false
                        }
                    }

                    sectionItem(
                        title: LocalizedString("Tube filling sound", comment: "Label for tube filling sound"),
                        isEditing: isEditingAlertAnnun,
                        value: $viewModel.alertAnnun
                    )
                    .onTapGesture {
                        withAnimation {
                            self.isEditingButtonAnnun = false
                            self.isEditingQuickBolusAnnun = false
                            self.isEditingBolusAnnun = false
                            self.isEditingReminderAnnun = false
                            self.isEditingAlarmAnnun = false
                            self.isEditingAlertAnnun = false
                            self.isEditingFillingTubeAnnun.toggle()
                        }
                    }
                }
            }

            Spacer()

            ContinueButton(text: LocalizedString("Save", comment: "label for save"), action: {})
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(LocalizedString("Sound settings", comment: "Sound view title"))
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
}
