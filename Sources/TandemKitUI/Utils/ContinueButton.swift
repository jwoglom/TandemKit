import LoopKitUI
import SwiftUI

struct ContinueButton: View {
    var text = LocalizedString("Continue", comment: "Text for continue button")
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

#Preview {
    ContinueButton(action: {})
}
