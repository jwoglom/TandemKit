//
//  ErrorSheet.swift
//  TandemKit
//
//  Created by James Woglom on 1/30/26.
//

import Foundation
import UIKit
import SwiftUI


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
                ZStack {
                    Text(LocalizedString(
                        "OK",
                        comment: "OK button"
                    ))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(tint)
                .foregroundColor(.primary)
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(tint)
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
