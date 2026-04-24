import Foundation
import LoopKitUI
import SwiftUI
import UIKit

struct ErrorSheetContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ErrorSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let content: ErrorSheetContent
    let tint: Color

    var body: some View {
        VStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(tint)
                Text(content.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(content.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Button(action: {
                dismiss()
            }) {
                Text("OK", comment: "OK button")
            }
            .buttonStyle(ActionButtonStyle())
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(24)
        .errorSheetDetents()
    }
}

private extension View {
    func errorSheetDetents() -> some View {
        if #available(iOS 16.0, *) {
            return AnyView(self.presentationDetents([.fraction(0.75)]))
        }
        return AnyView(self)
    }
}
