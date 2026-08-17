import SwiftUI

/// The title, message and buttons of a confirmation dialog.
///
/// This mirrors the shape of `ActionSheet` so call sites read the same, but it is
/// presented through `Alert` instead. `ActionSheet`/`actionSheet(...)` and
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
        let title: Text
        let role: ButtonRole?
        let action: () -> Void

        static func destructive(_ title: Text, action: @escaping () -> Void) -> Action {
            Action(title: title, role: .destructive, action: action)
        }

        static func standard(_ title: Text, action: @escaping () -> Void) -> Action {
            Action(title: title, role: nil, action: action)
        }

        /// SwiftUI moves the cancel-role button to the bottom of the dialog regardless
        /// of where it appears in `actions`.
        static func cancel(_ title: Text) -> Action {
            Action(title: title, role: .cancel, action: {})
        }
    }

    let title: Text
    let message: Text
    let actions: [Action]
}

private func alertButton(for action: ConfirmationDialogContent.Action) -> Alert.Button {
    switch action.role {
    case .destructive:
        return .destructive(action.title, action: action.action)
    case .cancel:
        return .cancel(action.title, action: action.action)
    default:
        return .default(action.title, action: action.action)
    }
}

private func makeAlert(for dialog: ConfirmationDialogContent) -> Alert {
    let cancelAction = dialog.actions.first { $0.role == .cancel }
    let otherActions = dialog.actions.filter { $0.role != .cancel }

    if let cancelAction, let primaryAction = otherActions.first {
        return Alert(
            title: dialog.title,
            message: dialog.message,
            primaryButton: alertButton(for: primaryAction),
            secondaryButton: alertButton(for: cancelAction)
        )
    } else if let onlyAction = dialog.actions.first {
        return Alert(title: dialog.title, message: dialog.message, dismissButton: alertButton(for: onlyAction))
    } else {
        return Alert(title: dialog.title, message: dialog.message)
    }
}

private struct ItemConfirmationDialog<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let dialog: (Item) -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        base.alert(item: $item) { item in
            makeAlert(for: dialog(item))
        }
    }
}

private struct BoolConfirmationDialog: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        base.alert(isPresented: $isPresented) {
            makeAlert(for: dialog())
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
