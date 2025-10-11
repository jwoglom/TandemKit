import XCTest
@testable import TandemCore

final class PumpStateSupplierTests: XCTestCase {
    func testSanitizeAndStoreLongPairingCode() throws {
        let sanitized = try MainActor.assumeIsolated { try PumpStateSupplier.sanitizeAndStorePairingCode("abcd-efgh-ijkl-mnop") }
        let storedCode = MainActor.assumeIsolated { PumpStateSupplier.pumpPairingCode?() }
        XCTAssertEqual(sanitized, "ABCDEFGHIJKLMNOP")
        XCTAssertEqual(storedCode, "ABCDEFGHIJKLMNOP")
    }

    func testSanitizeAndStoreShortPairingCode() throws {
        let sanitized = try MainActor.assumeIsolated { try PumpStateSupplier.sanitizeAndStorePairingCode("123-456") }
        let storedCode = MainActor.assumeIsolated { PumpStateSupplier.pumpPairingCode?() }
        XCTAssertEqual(sanitized, "123456")
        XCTAssertEqual(storedCode, "123456")
    }

    func testInvalidPairingCodeThrows() {
        XCTAssertThrowsError(try MainActor.assumeIsolated { try PumpStateSupplier.sanitizeAndStorePairingCode("12") }) { error in
            XCTAssertTrue(error is PumpPairingCodeValidationError)
        }
    }
}
