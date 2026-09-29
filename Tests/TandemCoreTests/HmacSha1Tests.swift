@testable import TandemKit
import XCTest

/// RFC 2202 section 3. Every signed request is authenticated with this.
final class HmacSha1Tests: XCTestCase {
    func testRFC2202ShortKey() {
        XCTAssertEqual(
            HmacSha1(data: Data("Hi There".utf8), key: Data(repeating: 0x0B, count: 20)).hexadecimalString,
            "b617318655057264e28bc0b6fb378c8ef146be00"
        )
    }

    func testRFC2202TextKey() {
        XCTAssertEqual(
            HmacSha1(data: Data("what do ya want for nothing?".utf8), key: Data("Jefe".utf8)).hexadecimalString,
            "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"
        )
    }

    func testRFC2202KeyLongerThanABlock() {
        XCTAssertEqual(
            HmacSha1(
                data: Data("Test Using Larger Than Block-Size Key - Hash Key First".utf8),
                key: Data(repeating: 0xAA, count: 80)
            ).hexadecimalString,
            "aa4ae5e15272d00e95705637ce8a3b55ed402112"
        )
    }
}
