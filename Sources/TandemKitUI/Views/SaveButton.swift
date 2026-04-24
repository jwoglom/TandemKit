import LoopKitUI
import SwiftUI

struct SaveButton: View {
    var text = Text("Save", comment: "Text for save button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
    var buttonStyle: ActionButtonStyle.ButtonType = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading.wrappedValue {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            } else {
                text
            }
        }
        .disabled(loading.wrappedValue || disabled.wrappedValue)
        .buttonStyle(ActionButtonStyle(buttonStyle))
    }
}

#Preview("Default") {
    SaveButton(text: Text("Save", comment: "save")) {}
        .padding()
}

#Preview("Loading") {
    SaveButton(
        text: Text("Saving", comment: "Saving"),
        loading: .constant(true),
        disabled: .constant(false)
    ) {}
        .padding()
}

#Preview("Disabled") {
    SaveButton(
        text: Text("Disabled", comment: "Disabled"),
        loading: .constant(false),
        disabled: .constant(true)
    ) {}
        .padding()
}
