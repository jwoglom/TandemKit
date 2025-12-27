//
//  LinearProgressBar.swift
//  TandemKit
//
//  Created by James Woglom on 12/27/25.
//

import SwiftUI
import SwiftUICore

struct ProgressBar: View {
    
    let value: CGFloat
    let total: CGFloat
    
    var body: some View {
        GeometryReader(content: { geometry in
            ZStack(alignment: .leading, content: {
                Rectangle()
                    .foregroundColor(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(Capsule())
                
                Rectangle()
                    .foregroundColor(.blue)
                    .frame(maxHeight: .infinity)
                    .frame(width: calculateBarWidth(contentWidth: geometry.size.width))
                    .clipShape(Capsule())
            })
            .clipped()
        })
    }
    
    private func calculateBarWidth(contentWidth: CGFloat) -> CGFloat {
        return (value / total) * contentWidth
    }
}
