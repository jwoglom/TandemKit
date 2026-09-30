import SwiftUI
import UIKit

struct TandemKitDebugView: View {
    @StateObject var viewModel: TandemKitDebugViewModel

    @State private var activeCategory: TandemKitDebugViewModel.CategoryGroup?
    @State private var showingPumpState = false
    @State private var showingManagerState = false
    @State private var showingRerunSetupConfirmation = false

    var body: some View {
        List {
            Section(header: Text("Send Pump Message")) {
                ForEach(viewModel.categories) { group in
                    Button {
                        activeCategory = group
                    } label: {
                        HStack {
                            Label(group.sendButtonTitle, systemImage: "paperplane")
                            Spacer()
                            Text("\(group.requests.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if viewModel.isSending {
                    ProgressView("Sending…")
                }

                if let response = viewModel.lastResponseDescription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response")
                            .font(.headline)
                        Text(response)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Pump response")
                    }

                    Button("Copy Response") {
                        UIPasteboard.general.string = response
                    }
                    .buttonStyle(.borderless)

                    Button("Resend") {
                        viewModel.resendLastMessage()
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isSending)
                }

                if let error = viewModel.lastSendError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            Section(header: Text("History Logs")) {
                Button {
                    viewModel.openHistoryLogViewer?()
                } label: {
                    Label("History Log Viewer", systemImage: "list.bullet.rectangle")
                }
                .disabled(viewModel.openHistoryLogViewer == nil)

                Button {
                    viewModel.openHistoryBackfill?()
                } label: {
                    Label("History Backfill Activity", systemImage: "clock.arrow.circlepath")
                }
                .disabled(viewModel.openHistoryBackfill == nil)
            }

            Section(header: Text("PumpState")) {
                Button("View PumpState") {
                    showingPumpState = true
                }
                .sheet(isPresented: $showingPumpState) {
                    DebugTextView(title: "PumpState", contents: viewModel.pumpStateJsonDebugDescription)
                }
            }

            Section(header: Text("TandemPumpManagerState")) {
                Button("View TandemPumpManagerState") {
                    showingManagerState = true
                }
                .sheet(isPresented: $showingManagerState) {
                    DebugTextView(title: "TandemPumpManagerState", contents: viewModel.managerStateJsonDebugDescription)
                }
            }

            Section {
                Button {
                    viewModel.openFeatureFlags?()
                } label: {
                    Label("Feature Flags", systemImage: "flag")
                }
                .disabled(viewModel.openFeatureFlags == nil)
            }

            Section(header: Text("Silent Tones")) {
                Toggle(isOn: Binding(
                    get: { viewModel.useSilentMode },
                    set: { viewModel.setSilentMode($0) }
                )) {
                    Text("Silent Tones", comment: "Label for silent tones")
                }
            }

            if viewModel.rerunInitialSetup != nil {
                Section(footer: Text("Re-runs pairing and the initial setup screens on the current pump. The pump manager is not removed.")) {
                    Button {
                        showingRerunSetupConfirmation = true
                    } label: {
                        Label("Re-run Pump Setup", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .navigationBarTitle("Debug Options", displayMode: .inline)
        .sheet(item: $activeCategory) { group in
            CategoryRequestSheet(viewModel: viewModel, group: group)
        }
        .alert("Re-run Pump Setup?", isPresented: $showingRerunSetupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-run Setup") {
                viewModel.rerunInitialSetup?()
            }
        } message: {
            Text("This deletes the saved pairing and restarts the initial setup flow for this pump (the pump manager is not removed). Re-pairing the pump requires a wireless charging pad — do not continue unless you have your pump charger available.")
        }
    }
}

/// Presents every request in a single category as a navigable list, mirroring the modal
/// presentation used by "View PumpState". Requests without parameters send immediately and
/// dismiss; requests that need input push a detail form.
private struct CategoryRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TandemKitDebugViewModel
    let group: TandemKitDebugViewModel.CategoryGroup

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(group.requests) { entry in
                        if entry.requiresInput {
                            NavigationLink {
                                RequestDetailView(viewModel: viewModel, entry: entry) {
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Button(entry.name) {
                                viewModel.sendSimpleEntry(entry)
                                dismiss()
                            }
                        }
                    }
                } footer: {
                    Text("Requests marked with a slider icon need parameters or raw cargo before sending.")
                }
            }
            .navigationTitle("\(group.category.rawValue) Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// Parameter entry / raw cargo form for a single request. Sending dismisses the entire
/// category sheet so the decoded response shows on the main Debug Options screen.
private struct RequestDetailView: View {
    @ObservedObject var viewModel: TandemKitDebugViewModel
    let entry: TandemKitDebugViewModel.RequestEntry
    let onSent: () -> Void

    var body: some View {
        Form {
            if let option = entry.parameterized, !option.fields.isEmpty {
                Section(header: Text("Parameters")) {
                    ForEach(option.fields) { field in
                        TextField(field.label, text: Binding(
                            get: { viewModel.parameterInput[field.id] ?? "" },
                            set: { viewModel.parameterInput[field.id] = $0 }
                        ))
                            .keyboardType(field.keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .overlay(alignment: .leading) {
                                if (viewModel.parameterInput[field.id] ?? "").isEmpty {
                                    Text(field.placeholder)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .opacity(0.6)
                                }
                            }
                    }
                }
            }

            Section(header: Text("Raw Cargo (hex optional)")) {
                TextEditor(text: $viewModel.cargoHexInput)
                    .frame(minHeight: 80)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }

            if let error = viewModel.lastSendError {
                Section(header: Text("Error")) {
                    Text(error)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button("Send") {
                    viewModel.sendEntry(entry)
                    if viewModel.lastSendError == nil {
                        onSent()
                    }
                }
                .disabled(viewModel.isSending)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.resetInput()
        }
    }
}

private struct DebugTextView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let contents: String

    var body: some View {
        NavigationView {
            ScrollView {
                Text(contents)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.leading, .trailing, .top])
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private extension TandemKitDebugViewModel.ParameterField {
    var keyboard: UIKeyboardType {
        switch type {
        case .integer,
             .unsigned:
            return .numberPad
        case .boolean:
            return .default
        }
    }
}

#Preview {
    TandemKitDebugView(viewModel: TandemKitDebugViewModel(pumpManager: nil))
}
