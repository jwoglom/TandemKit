import SwiftUI
import UIKit

struct TandemKitDebugView: View {
    @StateObject var viewModel: TandemKitDebugViewModel

    @State private var showingParameterized: TandemKitDebugViewModel.ParameterizedOption?
    @State private var showingPumpState = false
    @State private var showingManagerState = false

    var body: some View {
        List {
            Section(header: Text("Send Pump Message")) {
                Menu {
                    ForEach(viewModel.requestMessages, id: \.name) { metadata in
                        Button(action: {
                            viewModel.sendSimpleMessage(metadata)
                        }) {
                            Text(metadata.name)
                        }
                    }
                } label: {
                    Label("Send simple request", systemImage: "paperplane")
                }

                if !viewModel.parameterizedMessages.isEmpty {
                    Menu {
                        ForEach(viewModel.parameterizedMessages) { option in
                            Button(action: {
                                viewModel.parameterInput = [:]
                                viewModel.cargoHexInput = ""
                                showingParameterized = option
                            }) {
                                HStack {
                                    Text(option.metadata.name)
                                    Spacer()
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } label: {
                        Label("Send parameterized request", systemImage: "slider.horizontal.3")
                    }
                }

                if viewModel.isSending {
                    ProgressView("Sending…")
                }

                if let response = viewModel.lastResponseDescription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response")
                            .font(.headline)
                        TextEditor(text: .constant(response))
                            .frame(minHeight: 120)
                            .disabled(true)
                            .font(.system(.footnote, design: .monospaced))
                            .accessibilityLabel("Pump response")
                        Button("Resend") {
                            viewModel.resendLastMessage()
                        }
                        .disabled(viewModel.isSending)
                    }
                }

                if let error = viewModel.lastSendError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
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

            Section(header: Text("Silent Tones")) {
                Toggle(isOn: Binding(
                    get: { viewModel.useSilentMode },
                    set: { viewModel.setSilentMode($0) }
                )) {
                    Text("Silent Tones", comment: "Label for silent tones")
                }
            }
        }
        .navigationBarTitle("Debug Options", displayMode: .inline)
        .sheet(item: $showingParameterized) { option in
            ParameterizedMessageSheet(viewModel: viewModel, option: option)
        }
    }
}

private struct ParameterizedMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TandemKitDebugViewModel
    let option: TandemKitDebugViewModel.ParameterizedOption

    var body: some View {
        NavigationView {
            Form {
                if !option.fields.isEmpty {
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

                if let response = viewModel.lastResponseDescription {
                    Section(header: Text("Response")) {
                        TextEditor(text: .constant(response))
                            .frame(minHeight: 140)
                            .disabled(true)
                            .font(.system(.footnote, design: .monospaced))
                        Button("Resend") {
                            viewModel.resendLastMessage()
                        }
                        .disabled(viewModel.isSending)
                    }
                }

                if let error = viewModel.lastSendError {
                    Section(header: Text("Error")) {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(option.metadata.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        viewModel.sendParameterizedMessage(option)
                    }
                }
            }
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

extension TandemKitDebugViewModel.ParameterizedOption: Identifiable {
    var id: String { metadata.name }
}

#Preview {
    TandemKitDebugView(viewModel: TandemKitDebugViewModel(pumpManager: nil))
}
