import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitNotificationsView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitNotificationsViewModel
    @State private var didLoad = false

    var body: some View {
        List {
            if viewModel.isRefreshing && viewModel.notifications.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            Text("Loading notifications...", comment: "Loading notifications message")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else if viewModel.notifications.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("No notifications", comment: "No notifications message")
                                .font(.headline)
                            Text(
                                "Your pump has no active notifications",
                                comment: "No notifications detail message"
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        }
                        .padding()
                        Spacer()
                    }
                }
            } else {
                Section(header: SectionHeader(label: String(
                    localized:
                    "Active Notifications",
                    comment: "The title of the active notifications section"
                ))) {
                    ForEach(viewModel.notifications) { item in
                        NotificationRow(item: item, onDismiss: {
                            viewModel.dismissNotification(item)
                        })
                    }
                }
            }

            if let lastRefresh = viewModel.lastRefreshTime {
                Section {
                    HStack {
                        Text("Last updated", comment: "Last updated label")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                        Text(formatLastRefreshTime(lastRefresh))
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(String(localized: "Notifications", comment: "Notifications view title"))
        .navigationBarItems(trailing: refreshButton)
        .task {
            guard !didLoad else { return }
            didLoad = true
            viewModel.refreshNotifications()
        }
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { ErrorWrapper(message: $0) } },
            set: { _ in viewModel.clearError() }
        )) { error in
            Alert(
                title: Text("Error", comment: "Error alert title"),
                message: Text(error.message),
                dismissButton: .default(Text("OK", comment: "OK button"))
            )
        }
    }

    private var refreshButton: some View {
        Button(action: {
            viewModel.refreshNotifications()
        }) {
            if viewModel.isRefreshing {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isRefreshing)
    }

    private func formatLastRefreshTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NotificationRow: View {
    let item: NotificationItem
    let onDismiss: () -> Void
    var backgroundColor = Color(UIColor.systemBackground)

    @State private var offset: CGFloat = 0
    @State private var isDismissing = false

    private let dismissThreshold: CGFloat = -80

    var body: some View {
        ZStack {
            // Background delete button
            HStack {
                Spacer()
                if item.canDismiss {
                    VStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    }
                    .padding(.horizontal, 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(item.canDismiss ? Color.red : Color.clear)
            .cornerRadius(8)

            // Notification content
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.title)
                        .font(.body)
                }
                Spacer()

                if !item.canDismiss {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(backgroundColor)
            .cornerRadius(8)
            .offset(x: offset)
            .gesture(
                item.canDismiss ?
                    DragGesture()
                    .onChanged { gesture in
                        // Only allow left swipe
                        if gesture.translation.width < 0 {
                            offset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.width < dismissThreshold {
                            // Dismiss
                            withAnimation(.easeOut(duration: 0.3)) {
                                offset = -UIScreen.main.bounds.width
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDismiss()
                            }
                        } else {
                            // Snap back
                            withAnimation(.spring()) {
                                offset = 0
                            }
                        }
                    }
                    : nil
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

// Helper for alert with String binding
private struct ErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}

#Preview("With Notifications") {
    NavigationView {
        TandemKitNotificationsView(
            viewModel: TandemKitNotificationsViewModel.previewWithNotifications
        )
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Empty") {
    NavigationView {
        TandemKitNotificationsView(
            viewModel: TandemKitNotificationsViewModel.previewEmpty
        )
    }
    .environment(\.guidanceColors, GuidanceColors())
}

// Preview helpers
private extension TandemKitNotificationsViewModel {
    static var previewWithNotifications: TandemKitNotificationsViewModel {
        let viewModel = TandemKitNotificationsViewModel(nil)
        viewModel.notifications = [
            NotificationItem(type: .alert, id: 0, name: "LOW_INSULIN_ALERT"),
            NotificationItem(type: .reminder, id: 2, name: "SITE_CHANGE_REMINDER"),
            NotificationItem(type: .cgmAlert, id: 3, name: "LOW_CGM_ALERT"),
            NotificationItem(type: .malfunction, id: 1, name: "1-0x2026")
        ]
        viewModel.lastRefreshTime = Date()
        return viewModel
    }

    static var previewEmpty: TandemKitNotificationsViewModel {
        let viewModel = TandemKitNotificationsViewModel(nil)
        viewModel.notifications = []
        viewModel.lastRefreshTime = Date()
        return viewModel
    }
}
