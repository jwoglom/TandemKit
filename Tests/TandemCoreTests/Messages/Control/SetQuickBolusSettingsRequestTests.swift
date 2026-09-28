@testable import TandemKit
import XCTest

/// One test per cargo the Tandem Mobi app was captured sending (#428), which includes every
/// entry of pumpX2's `QuickBolusIncrement` magic table.
final class SetQuickBolusSettingsRequestTests: XCTestCase {
    private func assertCargo(
        _ hex: String,
        enabled: Bool,
        mode: QuickBolusMode,
        incrementUnits: Int,
        incrementCarbs: Int,
        changedFields: QuickBolusSettingsFields,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parsed = SetQuickBolusSettingsRequest(cargo: try XCTUnwrap(Data(hexadecimalString: hex), file: file, line: line))
        XCTAssertEqual(parsed.enabled, enabled, "enabled", file: file, line: line)
        XCTAssertEqual(parsed.mode, mode, "mode", file: file, line: line)
        XCTAssertEqual(parsed.incrementUnits, incrementUnits, "incrementUnits", file: file, line: line)
        XCTAssertEqual(parsed.incrementCarbs, incrementCarbs, "incrementCarbs", file: file, line: line)
        XCTAssertEqual(parsed.changedFields, changedFields, "changedFields", file: file, line: line)

        let built = SetQuickBolusSettingsRequest(
            enabled: enabled,
            mode: mode,
            incrementUnits: incrementUnits,
            incrementCarbs: incrementCarbs,
            changedFields: changedFields
        )
        XCTAssertEqual(built.cargo.hexadecimalString, hex, "built cargo", file: file, line: line)
    }

    // MARK: - Units

    func testDisableCarryingHalfUnit() throws {
        try assertCargo("0000f401d00701", enabled: false, mode: .units, incrementUnits: 500, incrementCarbs: 2000, changedFields: .enabled)
    }

    func testDisableCarryingOneUnit() throws {
        try assertCargo("0000e803d00701", enabled: false, mode: .units, incrementUnits: 1000, incrementCarbs: 2000, changedFields: .enabled)
    }

    func testDisableCarryingFiveUnits() throws {
        try assertCargo("00008813d00701", enabled: false, mode: .units, incrementUnits: 5000, incrementCarbs: 2000, changedFields: .enabled)
    }

    func testEnableCarryingHalfUnit() throws {
        try assertCargo("0100f401d00701", enabled: true, mode: .units, incrementUnits: 500, incrementCarbs: 2000, changedFields: .enabled)
    }

    func testEnableCarryingOneUnit() throws {
        try assertCargo("0100e803d00701", enabled: true, mode: .units, incrementUnits: 1000, incrementCarbs: 2000, changedFields: .enabled)
    }

    func testEnableAtOneUnit() throws {
        try assertCargo(
            "0100e803d00705",
            enabled: true,
            mode: .units,
            incrementUnits: 1000,
            incrementCarbs: 2000,
            changedFields: [.enabled, .incrementUnits]
        )
    }

    func testIncrementHalfUnit() throws {
        try assertCargo("0100f401d00704", enabled: true, mode: .units, incrementUnits: 500, incrementCarbs: 2000, changedFields: .incrementUnits)
    }

    func testIncrementOneUnit() throws {
        try assertCargo("0100e803d00704", enabled: true, mode: .units, incrementUnits: 1000, incrementCarbs: 2000, changedFields: .incrementUnits)
    }

    func testIncrementTwoUnits() throws {
        try assertCargo("0100d007d00704", enabled: true, mode: .units, incrementUnits: 2000, incrementCarbs: 2000, changedFields: .incrementUnits)
    }

    func testIncrementFiveUnits() throws {
        try assertCargo("01008813d00704", enabled: true, mode: .units, incrementUnits: 5000, incrementCarbs: 2000, changedFields: .incrementUnits)
    }

    // MARK: - Carbs

    func testSwitchToCarbs() throws {
        try assertCargo("01018813d00702", enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 2000, changedFields: .mode)
    }

    func testIncrementTwoGrams() throws {
        try assertCargo("01018813d00708", enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 2000, changedFields: .incrementCarbs)
    }

    func testIncrementFiveGrams() throws {
        try assertCargo("01018813881308", enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 5000, changedFields: .incrementCarbs)
    }

    func testIncrementTenGrams() throws {
        try assertCargo("01018813102708", enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 10000, changedFields: .incrementCarbs)
    }

    func testIncrementFifteenGrams() throws {
        try assertCargo("01018813983a08", enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 15000, changedFields: .incrementCarbs)
    }
}
