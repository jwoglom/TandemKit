import LoopKitUI
import SwiftUI

/// iPhone-style battery indicator: an outlined body with a proportional fill, a terminal nub,
/// and a punched-out bolt while charging.
///
/// Drawn rather than assembled from SF Symbols so the geometry is predictable enough to align
/// against adjacent text, and so the charging bolt is available below iOS 16.
struct BatteryIndicatorView: View {
    /// Remaining charge as a 0...1 fraction, or nil when the pump has not reported a level.
    let chargeRemaining: Double?
    /// Whether the pump is charging. Only newer pump API versions report this.
    let isCharging: Bool

    @Environment(\.guidanceColors) private var guidanceColors

    /// Height of the battery body. Every other dimension is derived from it so the indicator
    /// scales as a unit with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var bodyHeight: CGFloat = 12

    private var bodyWidth: CGFloat { bodyHeight * 2 }
    private var cornerRadius: CGFloat { bodyHeight / 3.5 }
    private var strokeWidth: CGFloat { max(1, bodyHeight / 12) }
    private var innerInset: CGFloat { strokeWidth * 1.5 }
    private var capWidth: CGFloat { max(1, bodyHeight / 6) }
    private var capHeight: CGFloat { bodyHeight / 3 }

    private var clampedCharge: Double? {
        chargeRemaining.map { min(max($0, 0), 1) }
    }

    /// Green while charging, critical at or below 20%, otherwise the foreground color (white in
    /// dark mode, black in light mode). An unknown level stays muted.
    ///
    /// Exposed so an adjacent percentage label can carry the same state color.
    static func tintColor(chargeRemaining: Double?, isCharging: Bool, guidanceColors: GuidanceColors) -> Color {
        if isCharging {
            return .green
        }
        guard let chargeRemaining = chargeRemaining else {
            return .secondary
        }
        return min(max(chargeRemaining, 0), 1) <= 0.2 ? guidanceColors.critical : .primary
    }

    private var tintColor: Color {
        Self.tintColor(chargeRemaining: clampedCharge, isCharging: isCharging, guidanceColors: guidanceColors)
    }

    var body: some View {
        HStack(spacing: strokeWidth) {
            ZStack(alignment: .leading) {
                // strokeBorder keeps the outline inside the frame so the drawn width is exact.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tintColor.opacity(0.4), lineWidth: strokeWidth)

                if let clampedCharge = clampedCharge, clampedCharge > 0 {
                    RoundedRectangle(cornerRadius: max(cornerRadius - innerInset, 0.5))
                        .fill(tintColor)
                        .frame(width: fillWidth(for: clampedCharge), height: bodyHeight - innerInset * 2)
                        .padding(.leading, innerInset)
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .overlay(chargingBoltCutout)
            // Lets the bolt cut through both the fill and the outline, the way iOS draws it.
            .compositingGroup()
            // Drawn after the compositing group so it paints over the empty part of the body
            // instead of punching a hole in it.
            .overlay(chargingBoltHighlight)

            RoundedRectangle(cornerRadius: capWidth / 2)
                .fill(tintColor.opacity(0.4))
                .frame(width: capWidth, height: capHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// The bolt is drawn twice, split at the edge of the level fill: the part over the fill is
    /// punched out, and the part over the empty body is painted in. Punching alone left the bolt
    /// invisible wherever it extended past the fill, so a charging pump above roughly 40% was the
    /// only case where the bolt read clearly.
    private var boltImage: some View {
        Image(systemName: "bolt.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: bodyHeight * 0.75)
            .frame(width: bodyWidth, height: bodyHeight)
    }

    /// The half of the bolt sitting on top of the level fill, knocked out of it.
    @ViewBuilder
    private var chargingBoltCutout: some View {
        if isCharging {
            boltImage
                .mask(boltMask(overFill: true))
                .blendMode(.destinationOut)
        }
    }

    /// The half of the bolt sitting on the empty part of the body, drawn in the tint color.
    @ViewBuilder
    private var chargingBoltHighlight: some View {
        if isCharging {
            boltImage
                .foregroundColor(tintColor)
                .mask(boltMask(overFill: false))
        }
    }

    /// Splits the body at the fill edge, keeping either the filled or the empty side.
    private func boltMask(overFill: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .frame(width: fillEdgeX)
                .opacity(overFill ? 1 : 0)
            Rectangle()
                .opacity(overFill ? 0 : 1)
        }
        .frame(width: bodyWidth, height: bodyHeight)
    }

    /// Distance from the leading edge of the body to the trailing edge of the level fill.
    private var fillEdgeX: CGFloat {
        guard let clampedCharge = clampedCharge, clampedCharge > 0 else { return 0 }
        return innerInset + fillWidth(for: clampedCharge)
    }

    private func fillWidth(for charge: Double) -> CGFloat {
        let available = bodyWidth - innerInset * 2
        // Keep a sliver visible at very low charge rather than collapsing to nothing.
        return max(available * CGFloat(charge), innerInset)
    }

    private var accessibilityDescription: String {
        guard let clampedCharge = clampedCharge else {
            return String(localized: "Pump battery level unknown", comment: "accessibility label for unknown pump battery level")
        }

        let percentage = Int((clampedCharge * 100).rounded())
        if isCharging {
            return String(
                format: String(
                    localized: "Pump battery %d percent, charging",
                    comment: "accessibility label for pump battery level while charging"
                ),
                percentage
            )
        }

        return String(
            format: String(
                localized: "Pump battery %d percent",
                comment: "accessibility label for pump battery level"
            ),
            percentage
        )
    }
}

#Preview("Battery states") {
    VStack(alignment: .leading, spacing: 12) {
        BatteryIndicatorView(chargeRemaining: 1.0, isCharging: false)
        BatteryIndicatorView(chargeRemaining: 0.55, isCharging: false)
        BatteryIndicatorView(chargeRemaining: 0.2, isCharging: false)
        BatteryIndicatorView(chargeRemaining: 0.05, isCharging: false)
        BatteryIndicatorView(chargeRemaining: 1.0, isCharging: true)
        BatteryIndicatorView(chargeRemaining: 0.65, isCharging: true)
        BatteryIndicatorView(chargeRemaining: 0.4, isCharging: true)
        BatteryIndicatorView(chargeRemaining: 0.1, isCharging: true)
        BatteryIndicatorView(chargeRemaining: 0, isCharging: true)
        BatteryIndicatorView(chargeRemaining: nil, isCharging: false)
    }
    .padding()
}
