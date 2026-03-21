import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitAlertSettingsView: View {
    @ObservedObject var viewModel: TandemKitSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Alert Settings", comment: "Title for alert settings screen"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            Text(LocalizedString(
                "Configure how your pump handles alerts and notifications.",
                comment: "Description for alert settings"
            ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider()

            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.autoAcknowledgeBasalAlerts },
                        set: { viewModel.setAutoAcknowledgeBasalAlerts($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedString(
                                "Auto-Acknowledge Basal Alerts",
                                comment: "Label for auto-acknowledge basal alerts toggle"
                            ))
                            Text(LocalizedString(
                                "Automatically dismiss min/max basal rate alerts during looping",
                                comment: "Description for auto-acknowledge basal alerts toggle"
                            ))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.alertSnoozeEnabled },
                        set: { enabled in
                            viewModel.setAlertSnooze(enabled: enabled, durationMins: viewModel.alertSnoozeDurationMins)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedString(
                                "Alert Snooze",
                                comment: "Label for alert snooze toggle"
                            ))
                            Text(LocalizedString(
                                "Allow snoozing alerts via triple-press on pump button",
                                comment: "Description for alert snooze toggle"
                            ))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if viewModel.alertSnoozeEnabled {
                        Picker(
                            LocalizedString("Snooze Duration", comment: "Label for snooze duration picker"),
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
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
}
