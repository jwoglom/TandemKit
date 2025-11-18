import LoopKitUI
import SwiftUI

struct SaveButton: View {
    var text = LocalizedString("Save", comment: "Text for save button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading.wrappedValue {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            } else {
                Text(text)
            }
        }
        .disabled(loading.wrappedValue || disabled.wrappedValue)
    }
}
