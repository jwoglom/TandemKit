import SwiftUI
import UIKit

/// The title, message and buttons of a confirmation dialog.
///
/// This mirrors the shape of `ActionSheet` so call sites read the same, but it is
/// presented as an alert instead. `ActionSheet`/`actionSheet(...)` and
/// `confirmationDialog(...)` are both implemented as a popover-style
/// `UIAlertController(style: .actionSheet)` under the hood, which needs a source
/// anchor (`sourceView`/`sourceRect`). When one of these dialogs is attached to a
/// full-screen container - such as the fill-cannula, fill-tubing, and
/// change-cartridge wizard steps - SwiftUI computes that anchor from the container's
/// bounds instead of screen center, so the dialog renders as a small card pinned near
/// the top of the screen, overlapping the step progress bar and nav buttons. `Alert`
/// has no such anchor requirement and always renders as a centered, modal card. For a
/// dialog that gates suspending or resuming insulin delivery that is a safety
/// problem, not just a layout one.
struct ConfirmationDialogContent {
    struct Action {
        /// An alert drops any styling on a button's label; only the role and `isPreferred` reach UIKit.
        let title: Text
        let role: ButtonRole?
        var isPreferred = false
        let action: () -> Void

        static func destructive(_ title: Text, action: @escaping () -> Void) -> Action {
            Action(title: title, role: .destructive, action: action)
        }

        static func standard(_ title: Text, action: @escaping () -> Void) -> Action {
            Action(title: title, role: nil, action: action)
        }

        /// The alert's preferred action, which iOS emphasizes over the cancel button it would
        /// otherwise emphasize.
        static func primary(_ title: Text, action: @escaping () -> Void) -> Action {
            Action(title: title, role: nil, isPreferred: true, action: action)
        }

        /// SwiftUI moves the cancel-role button to the bottom of the dialog regardless
        /// of where it appears in `actions`.
        static func cancel(_ title: Text, action: @escaping () -> Void = {}) -> Action {
            Action(title: title, role: .cancel, action: action)
        }
    }

    let title: Text
    let message: Text
    let actions: [Action]

    var hasPreferredAction: Bool {
        actions.contains(where: \.isPreferred)
    }
}

/// The preferred action's label takes the host's tint over iOS's blue fill, which is unreadable, and
/// SwiftUI gives no way to style it. So once the alert is up, this draws that one label white.
private struct PreferredActionLabelColor: UIViewRepresentable {
    let isPresented: Bool

    private static let log = TandemLogger(category: "ConfirmationDialog")
    private static let pollInterval: TimeInterval = 0.05
    private static let pollAttempts = 20

    final class Coordinator {
        var wasPresented = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let wasPresented = context.coordinator.wasPresented
        context.coordinator.wasPresented = isPresented
        guard isPresented, !wasPresented else { return }
        Self.recolorWhenPresented(from: view, attemptsLeft: Self.pollAttempts)
    }

    // SwiftUI presents the alert a runloop or more after the binding flips.
    private static func recolorWhenPresented(from view: UIView, attemptsLeft: Int) {
        guard let alert = topPresentedController(in: view.window) as? UIAlertController else {
            guard attemptsLeft > 0 else {
                log.info("No alert came up to recolor the preferred action of")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak view] in
                guard let view else { return }
                recolorWhenPresented(from: view, attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        recolorPreferredAction(of: alert)
        // The fill and labels are laid out during the presentation, which can reset the color.
        alert.transitionCoordinator?.animate(alongsideTransition: nil) { _ in
            recolorPreferredAction(of: alert)
        }
    }

    private static func topPresentedController(in window: UIWindow?) -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private static func recolorPreferredAction(of alert: UIAlertController) {
        guard let title = alert.preferredAction?.title else {
            log.info("Alert has no preferred action, so its label keeps the tint")
            return
        }
        let labels = labels(in: alert.view).filter { $0.text == title }
        if labels.isEmpty {
            log.info("Alert has no label for its preferred action, so it keeps the tint")
        }
        for label in labels {
            label.textColor = .white
        }
    }

    private static func labels(in view: UIView) -> [UILabel] {
        if let label = view as? UILabel { return [label] }
        return view.subviews.flatMap(labels(in:))
    }
}

@ViewBuilder
private func alertButton(for action: ConfirmationDialogContent.Action) -> some View {
    // An alert takes its preferred action from the default-action shortcut; `Alert.Button`
    // has no way to set one, which is why this isn't built on `Alert`.
    if action.isPreferred {
        Button(role: action.role, action: action.action) { action.title }
            .keyboardShortcut(.defaultAction)
    } else {
        Button(role: action.role, action: action.action) { action.title }
    }
}

@ViewBuilder
private func alertButtons(for dialog: ConfirmationDialogContent) -> some View {
    if let action = dialog.actions.first(where: { $0.role != .cancel }) {
        alertButton(for: action)
    }
    if let cancelAction = dialog.actions.first(where: { $0.role == .cancel }) {
        alertButton(for: cancelAction)
    }
}

private struct ItemConfirmationDialog<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let dialog: (Item) -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        base.background(
            PreferredActionLabelColor(isPresented: item.map { dialog($0).hasPreferredAction } ?? false)
        ).alert(
            item.map { dialog($0).title } ?? Text(verbatim: ""),
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            presenting: item
        ) { item in
            alertButtons(for: dialog(item))
        } message: { item in
            dialog(item).message
        }
    }
}

private struct BoolConfirmationDialog: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        let content = dialog()
        return base.background(
            PreferredActionLabelColor(isPresented: isPresented && content.hasPreferredAction)
        ).alert(content.title, isPresented: $isPresented) {
            alertButtons(for: content)
        } message: {
            content.message
        }
    }
}

extension View {
    /// Presents a confirmation alert whose content is driven by an optional item.
    ///
    /// Replaces `actionSheet(item:)`/`confirmationDialog(item:)`.
    func confirmationAlert<Item: Identifiable>(
        item: Binding<Item?>,
        content: @escaping (Item) -> ConfirmationDialogContent
    ) -> some View {
        modifier(ItemConfirmationDialog(item: item, dialog: content))
    }

    /// Presents a confirmation alert with fixed content.
    ///
    /// Replaces `actionSheet(isPresented:)`/`confirmationDialog(isPresented:)`.
    func confirmationAlert(
        isPresented: Binding<Bool>,
        content: @escaping () -> ConfirmationDialogContent
    ) -> some View {
        modifier(BoolConfirmationDialog(isPresented: isPresented, dialog: content))
    }
}
