import SwiftUI

/// The title, message and buttons of a confirmation dialog.
///
/// This mirrors the shape of `ActionSheet` so call sites read the same, but it is
/// presented through `confirmationDialog` instead. `ActionSheet` and the
/// `actionSheet(...)` modifiers have been deprecated since iOS 15, and once the host
/// app links against the iOS 26 SDK they are presented as a popover with no source
/// anchor: the dialog is drawn over the navigation bar and loses its title, message
/// and cancel button, leaving only the confirming action on screen. For a dialog that
/// gates suspending or resuming insulin delivery that is a safety problem, not just a
/// layout one.
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

@ViewBuilder
private func confirmationDialogActions(for dialog: ConfirmationDialogContent) -> some View {
    ForEach(dialog.actions.indices, id: \.self) { index in
        let action = dialog.actions[index]
        Button(role: action.role, action: action.action) {
            action.title
        }
    }
}

private struct ItemConfirmationDialog<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let dialog: (Item) -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        let presented = item.map(dialog)

        return base.confirmationDialog(
            presented?.title ?? Text(verbatim: ""),
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            titleVisibility: .visible,
            presenting: presented
        ) { content in
            confirmationDialogActions(for: content)
        } message: { content in
            content.message
        }
    }
}

private struct BoolConfirmationDialog: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> ConfirmationDialogContent

    func body(content base: Content) -> some View {
        let presented = dialog()

        return base.confirmationDialog(
            presented.title,
            isPresented: $isPresented,
            titleVisibility: .visible,
            presenting: presented
        ) { content in
            confirmationDialogActions(for: content)
        } message: { content in
            content.message
        }
    }
}

extension View {
    /// Presents a confirmation dialog whose content is driven by an optional item.
    ///
    /// Replaces `actionSheet(item:)`.
    func confirmationDialog<Item: Identifiable>(
        item: Binding<Item?>,
        content: @escaping (Item) -> ConfirmationDialogContent
    ) -> some View {
        modifier(ItemConfirmationDialog(item: item, dialog: content))
    }

    /// Presents a confirmation dialog with fixed content.
    ///
    /// Replaces `actionSheet(isPresented:)`.
    func confirmationDialog(
        isPresented: Binding<Bool>,
        content: @escaping () -> ConfirmationDialogContent
    ) -> some View {
        modifier(BoolConfirmationDialog(isPresented: isPresented, dialog: content))
    }
}
