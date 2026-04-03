import LoopKitUI
import SwiftUI

struct ContinueButton: View {
    var text = Text("Continue", comment: "Text for continue button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
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
        .buttonStyle(ActionButtonStyle())
    }
}

#Preview {
    ContinueButton(action: {})
}
