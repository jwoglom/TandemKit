import LoopKitUI
import SwiftUI

struct TandemKitReconciliationView: View {
    @StateObject var viewModel: TandemKitReconciliationViewModel
    @Environment(\.guidanceColors) private var guidanceColors

    var body: some View {
        List {
            Section {
                ForEach(viewModel.status) { row in
                    RowView(row: row)
                }
            }

            Section {
                if viewModel.discrepancies.isEmpty {
                    Label(
                        String(localized: "None", comment: "Reconciliation screen: no discrepancies"),
                        systemImage: "checkmark.circle"
                    )
                    .foregroundColor(guidanceColors.acceptable)
                } else {
                    ForEach(viewModel.discrepancies) { row in
                        RowView(row: row)
                    }
                }
            } header: {
                Text("Discrepancies", comment: "Reconciliation screen: header for what the app was not told")
            } footer: {
                Text(
                    "What the pump did that the app was not told, or was told differently, as far as the driver can see.",
                    comment: "Reconciliation screen: footer for the discrepancies section"
                )
            }

            Section {
                if viewModel.passes.isEmpty {
                    Text("No history pass has run since launch.", comment: "Reconciliation screen: no passes yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.passes) { row in
                        RowView(row: row)
                    }
                }
            } header: {
                Text("History passes", comment: "Reconciliation screen: header for the recent history passes")
            } footer: {
                Text(
                    "One pass follows each read of the pump's history log. Newest first; the last 20 since launch.",
                    comment: "Reconciliation screen: footer for the history passes section"
                )
            }

            Section {
                if viewModel.differences.isEmpty {
                    Text("Every basal cycle compared so far matched.", comment: "Reconciliation screen: no basal differences")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.differences) { row in
                        RowView(row: row)
                    }
                }
            } header: {
                Text("Basal differences", comment: "Reconciliation screen: header for the basal cycles that differ")
            } footer: {
                Text(
                    "Each 5-minute pump cycle whose rate differs from what the app counts, and what was done about it. The last 50 since launch.",
                    comment: "Reconciliation screen: footer for the basal differences section"
                )
            }
        }
        .navigationBarTitle(
            String(localized: "Reconciliation", comment: "Title for the reconciliation debug screen"),
            displayMode: .inline
        )
        .refreshable {
            viewModel.refresh()
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

private struct RowView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    let row: TandemKitReconciliationViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                Spacer()
                if let value = row.value {
                    Text(value)
                        .foregroundColor(row.isWarning ? guidanceColors.warning : .secondary)
                        .multilineTextAlignment(.trailing)
                }
                if row.isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(guidanceColors.warning)
                }
            }
            if let detail = row.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
    }
}

#Preview {
    NavigationView {
        TandemKitReconciliationView(viewModel: TandemKitReconciliationViewModel(pumpManager: nil))
    }
}
