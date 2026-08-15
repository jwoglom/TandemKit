import SwiftUI

struct TandemKitFeatureFlagsView: View {
    @StateObject var viewModel: TandemKitFeatureFlagsViewModel

    /// Triple-tapping the pump image reveals the flags. Not persisted: the list goes back into
    /// hiding whenever the screen is left with every flag off.
    @State private var isRevealed = false

    var body: some View {
        Group {
            if isRevealed || viewModel.hasEnabledFlag {
                flagList
            } else {
                emptyState
            }
        }
        .navigationBarTitle("Feature Flags", displayMode: .inline)
    }

    private var emptyState: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Image(imageName: "tandem_mobi")
                    .resizable()
                    .rotationEffect(.degrees(90))
                    .scaledToFit()
                    .frame(height: 96)
                    .onTapGesture(count: 3) {
                        withAnimation { isRevealed = true }
                    }

                Text("No feature flags enabled.", comment: "Empty state for the feature flags screen")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var flagList: some View {
        List {
            Section(footer: Text(
                "Feature flags turn on driver features that are still being validated. Leave them off unless you have been asked to test one.",
                comment: "Footer explaining what feature flags are"
            )) {
                ForEach(viewModel.flags) { flag in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { viewModel.isEnabled(flag) },
                            set: { viewModel.setFlag(flag, enabled: $0) }
                        )) {
                            Text(flag.title)
                        }

                        Text(flag.flagDescription)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

#Preview {
    NavigationView {
        TandemKitFeatureFlagsView(viewModel: TandemKitFeatureFlagsViewModel(pumpManager: nil))
    }
}
