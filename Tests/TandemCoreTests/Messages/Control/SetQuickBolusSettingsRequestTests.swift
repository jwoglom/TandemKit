@testable import TandemKit
import XCTest

/// Cargos captured from the Tandem Mobi app (#428).
final class SetQuickBolusSettingsRequestTests: XCTestCase {
    private func parse(_ hex: String) throws -> SetQuickBolusSettingsRequest {
        SetQuickBolusSettingsRequest(cargo: try XCTUnwrap(Data(hexadecimalString: hex)))
    }

    func testDisable() throws {
        let request = try parse("00008813d00701")
        XCTAssertFalse(request.enabled)
        XCTAssertEqual(request.mode, .units)
        XCTAssertEqual(request.incrementUnits, 5000)
        XCTAssertEqual(request.incrementCarbs, 2000)
        XCTAssertEqual(request.changedFields, .enabled)
    }

    func testEnableAtOneUnit() throws {
        let request = try parse("0100e803d00705")
        XCTAssertTrue(request.enabled)
        XCTAssertEqual(request.incrementUnits, 1000)
        XCTAssertEqual(request.changedFields, [.enabled, .incrementUnits])
    }

    func testSwitchToCarbs() throws {
        let request = try parse("01018813d00702")
        XCTAssertEqual(request.mode, .carbs)
        XCTAssertEqual(request.changedFields, .mode)
    }

    func testCarbIncrement() throws {
        let request = try parse("01018813102708")
        XCTAssertEqual(request.incrementCarbs, 10000)
        XCTAssertEqual(request.changedFields, .incrementCarbs)
    }

    func testBuildMatchesTheCapturedCargo() {
        let request = SetQuickBolusSettingsRequest(
            enabled: true,
            mode: .units,
            incrementUnits: 1000,
            incrementCarbs: 2000,
            changedFields: [.enabled, .incrementUnits]
        )
        XCTAssertEqual(request.cargo.hexadecimalString, "0100e803d00705")
    }
}
