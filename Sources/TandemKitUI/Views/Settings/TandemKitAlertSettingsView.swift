import LoopKitUI
import SwiftUI

struct TandemKitAlertSettingsView: View {
    @ObservedObject var viewModel: TandemKitAlertSettingsViewModel

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.alertSnoozeEnabled },
                    set: { enabled in
                        viewModel.setAlertSnooze(enabled: enabled, durationMins: viewModel.alertSnoozeDurationMins)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            "Alert Snooze",
                            comment: "Label for alert snooze toggle"
                        )
                        Text(
                            "Allow snoozing alerts via triple-press on pump button",
                            comment: "Description for alert snooze toggle"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                if viewModel.alertSnoozeEnabled {
                    Picker(
                        String(localized: "Snooze Duration", comment: "Label for snooze duration picker"),
                        selection: Binding(
                            get: { viewModel.alertSnoozeDurationMins },
                            set: { mins in
                                viewModel.setAlertSnooze(enabled: true, durationMins: mins)
                            }
                        )
                    ) {
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                    }
                }
            } footer: {
                Text(
                    "Configure how your pump handles alerts and notifications.",
                    comment: "Description for alert settings"
                )
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}
