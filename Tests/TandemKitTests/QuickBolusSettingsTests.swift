@testable import TandemKit
import XCTest

/// #428. Expected cargos are the Tandem Mobi app's own writes for the same change.
@available(macOS 13.0, iOS 14.0, *) final class QuickBolusSettingsTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 0))
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func globals(
        enabled: Bool,
        mode: QuickBolusMode = .units,
        incrementUnits: Int,
        incrementCarbs: Int = 2000
    ) -> PumpGlobalsResponse {
        PumpGlobalsResponse(
            quickBolusEnabledRaw: enabled ? 1 : 0,
            quickBolusIncrementUnits: incrementUnits,
            quickBolusIncrementCarbs: incrementCarbs,
            quickBolusEntryType: mode.rawValue,
            quickBolusStatus: 1,
            buttonAnnun: 0,
            quickBolusAnnun: 0,
            generalAnnun: 0,
            reminderAnnun: 0,
            alertAnnun: 0,
            alarmAnnun: 0,
            fillTubingAnnun: 0
        )
    }

    private func set(enabled: Bool, incrementUnits: Int) -> Bool {
        let done = expectation(description: "setQuickBolusSettings")
        var result = false
        manager.setQuickBolusSettings(enabled: enabled, incrementUnits: incrementUnits) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func sentCargo() throws -> String {
        try XCTUnwrap(bluetooth.sent(SetQuickBolusSettingsRequest.self).first).cargo.hexadecimalString
    }

    func testEnablingSendsTheEnabledAndIncrementFieldsTogether() throws {
        bluetooth.enqueue(PumpGlobalsRequest.self, responses: [
            globals(enabled: false, incrementUnits: 500),
            globals(enabled: true, incrementUnits: 1000)
        ])

        XCTAssertTrue(set(enabled: true, incrementUnits: 1000))
        XCTAssertEqual(try sentCargo(), "0100e803d00705")
    }

    func testChangingTheIncrementLeavesTheEnabledFieldUnchanged() throws {
        bluetooth.enqueue(PumpGlobalsRequest.self, responses: [
            globals(enabled: true, incrementUnits: 1000),
            globals(enabled: true, incrementUnits: 2000)
        ])

        XCTAssertTrue(set(enabled: true, incrementUnits: 2000))
        XCTAssertEqual(try sentCargo(), "0100d007d00704")
    }

    func testDisablingCarriesThePumpsCurrentIncrements() throws {
        bluetooth.enqueue(PumpGlobalsRequest.self, responses: [
            globals(enabled: true, incrementUnits: 5000),
            globals(enabled: false, incrementUnits: 5000)
        ])

        XCTAssertTrue(set(enabled: false, incrementUnits: 5000))
        XCTAssertEqual(try sentCargo(), "00008813d00701")
    }

    func testSavingOnACarbsModePumpSwitchesItBackToUnits() throws {
        bluetooth.enqueue(PumpGlobalsRequest.self, responses: [
            globals(enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 10000),
            globals(enabled: true, mode: .units, incrementUnits: 5000, incrementCarbs: 10000)
        ])

        XCTAssertTrue(set(enabled: true, incrementUnits: 5000))
        XCTAssertEqual(try sentCargo(), "01008813102702")
    }

    func testAChangeThePumpDidNotApplyFailsTheSave() {
        bluetooth.stub(PumpGlobalsRequest.self, with: globals(enabled: true, mode: .carbs, incrementUnits: 500))

        XCTAssertFalse(set(enabled: true, incrementUnits: 500))
        XCTAssertTrue(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testNothingIsWrittenWhenThePumpAlreadyMatches() {
        bluetooth.stub(PumpGlobalsRequest.self, with: globals(enabled: true, incrementUnits: 2000))

        XCTAssertTrue(set(enabled: true, incrementUnits: 2000))
        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testUnsupportedIncrementIsRefusedWithoutTalkingToThePump() {
        XCTAssertFalse(set(enabled: true, incrementUnits: 750))
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
