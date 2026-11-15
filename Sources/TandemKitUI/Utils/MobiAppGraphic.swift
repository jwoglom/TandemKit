import ImageIO
import SwiftUI
import UIKit

/// Animations from Tandem's Mobi app, in `Media.xcassets/MobiAppGraphics`. The static
/// `mobi_six_digit_pairing` image there loads with `Image(imageName:)`.
enum MobiAppGraphic: String, CaseIterable {
    case placeOnPad = "place_on_pad"
    case pressAndHold = "press_and_hold"
    case pressTwice = "press_twice"
    case disconnectInfusionSet = "disconnect_infusion_set"
    case fillTubing = "fill_tubing"
    case newInfusionSet = "new_infusion_set"
    case removeCartridge = "remove_cartridge"
    case fillingStopped = "filling_stopped"

    /// A data set varies by neither appearance nor scale, so each variant is a data set of its own,
    /// named as in Tandem's app.
    func assetName(colorScheme: ColorScheme, displayScale: CGFloat) -> String {
        "\(colorScheme == .dark ? "dm" : "lm")_\(rawValue)@\(displayScale > 2 ? 3 : 2)x"
    }

    func gifData(colorScheme: ColorScheme, displayScale: CGFloat) -> Data? {
        let name = assetName(colorScheme: colorScheme, displayScale: displayScale)
        guard let asset = NSDataAsset(name: name, bundle: Bundle(for: TandemUICoordinator.self)) else {
            assertionFailure("Missing asset \(name) in TandemKitUI bundle")
            return nil
        }
        return asset.data
    }
}

struct MobiAppGraphicView: View {
    let graphic: MobiAppGraphic

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let data = graphic.gifData(colorScheme: colorScheme, displayScale: displayScale)
        AnimatedGIF(data: data, animates: !reduceMotion)
            .aspectRatio(data.flatMap(AnimatedGIFView.aspectRatio(of:)) ?? 1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct AnimatedGIF: UIViewRepresentable {
    let data: Data?
    let animates: Bool

    func makeUIView(context _: Context) -> AnimatedGIFView {
        let view = AnimatedGIFView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: AnimatedGIFView, context _: Context) {
        view.update(data: data, animates: animates)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView _: AnimatedGIFView, context _: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// Decodes one frame at a time: a whole animation decoded up front (480 frames at 600×480) would
/// take over 500 MB.
final class AnimatedGIFView: UIImageView {
    private var data: Data?
    private var animates = true
    private var generation = 0

    static func aspectRatio(of data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              height > 0
        else { return nil }
        return width / height
    }

    func update(data: Data?, animates: Bool) {
        guard data != self.data || animates != self.animates else { return }
        self.data = data
        self.animates = animates
        restart()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    private func restart() {
        generation += 1
        guard let data else {
            image = nil
            return
        }
        guard animates, window != nil else {
            image = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
                .map { UIImage(cgImage: $0) }
            return
        }
        let current = generation
        // ImageIO calls the block on the main queue.
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else {
                    stop.pointee = true
                    return
                }
                self.image = UIImage(cgImage: frame)
            }
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
            ForEach(MobiAppGraphic.allCases, id: \.self) { graphic in
                VStack {
                    MobiAppGraphicView(graphic: graphic)
                    Text(graphic.rawValue).font(.caption)
                }
            }
            VStack {
                Image(imageName: "mobi_six_digit_pairing")
                Text("mobi_six_digit_pairing").font(.caption)
            }
        }
        .padding()
    }
}
