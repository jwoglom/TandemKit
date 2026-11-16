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

    func testTheReplaceCartridgeGraphicRunsLongerThanTheRemovalItIsBuiltFrom() throws {
        func duration(_ graphic: MobiAppGraphic) throws -> Double {
            let data = try XCTUnwrap(graphic.gifData(colorScheme: .light, displayScale: 2))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            return (0 ..< CGImageSourceGetCount(source)).reduce(0) { total, index in
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                return total + ((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0)
            }
        }

        // 231 frames out and 229 back at 20 ms, against the source's 330.
        XCTAssertEqual(try duration(.replaceCartridge), 9.2, accuracy: 0.01)
        XCTAssertEqual(try duration(.removeCartridge), 6.6, accuracy: 0.01)
    }

    func testSixDigitPairingImageLoads() {
        XCTAssertNotNil(UIImage(named: "mobi_six_digit_pairing", in: Bundle(for: TandemUICoordinator.self), compatibleWith: nil))
    }
}
