import ImageIO
import SwiftUI
@testable import TandemKit
import XCTest

final class MobiAppGraphicTests: XCTestCase {
    func testEveryGraphicHasAnAnimatedGIFForEachAppearanceAndScale() throws {
        for graphic in MobiAppGraphic.allCases {
            for colorScheme in [ColorScheme.light, .dark] {
                for displayScale: CGFloat in [2, 3] {
                    let name = graphic.assetName(colorScheme: colorScheme, displayScale: displayScale)
                    let data = try XCTUnwrap(graphic.gifData(colorScheme: colorScheme, displayScale: displayScale), name)
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), name)
                    XCTAssertGreaterThan(CGImageSourceGetCount(source), 1, name)
                    XCTAssertNotNil(AnimatedGIFView.aspectRatio(of: data), name)
                }
            }
        }
    }

    func testSixDigitPairingImageLoads() {
        XCTAssertNotNil(UIImage(named: "mobi_six_digit_pairing", in: Bundle(for: TandemUICoordinator.self), compatibleWith: nil))
    }
}
