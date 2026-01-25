import LoopKitUI
import SwiftUI

struct SaveButton: View {
    var text = LocalizedString("Save", comment: "Text for save button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if loading.wrappedValue {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                } else {
                    Text(text)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .disabled(loading.wrappedValue || disabled.wrappedValue)
        .buttonStyle(.plain)
    }
}

#Preview("Default") {
    SaveButton(text: "Save") {}
        .padding()
}

#Preview("Loading") {
    SaveButton(
        text: "Saving",
        loading: .constant(true),
        disabled: .constant(false)
    ) {}
        .padding()
}

#Preview("Disabled") {
    SaveButton(
        text: "Disabled",
        loading: .constant(false),
        disabled: .constant(true)
    ) {}
        .padding()
}
