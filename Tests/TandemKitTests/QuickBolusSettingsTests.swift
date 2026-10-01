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

    private func assertSends(
        _ hex: String,
        from before: PumpGlobalsResponse,
        to after: PumpGlobalsResponse,
        enabled: Bool,
        incrementUnits: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        bluetooth.enqueue(PumpGlobalsRequest.self, responses: [before, after])

        XCTAssertTrue(set(enabled: enabled, incrementUnits: incrementUnits), file: file, line: line)
        XCTAssertEqual(try sentCargo(), hex, file: file, line: line)
    }

    func testEnablingAtTheCurrentHalfUnit() throws {
        try assertSends(
            "0100f401d00701",
            from: .quickBolus(enabled: false, incrementUnits: 500),
            to: .quickBolus(enabled: true, incrementUnits: 500),
            enabled: true,
            incrementUnits: 500
        )
    }

    func testEnablingAtTheCurrentOneUnit() throws {
        try assertSends(
            "0100e803d00701",
            from: .quickBolus(enabled: false, incrementUnits: 1000),
            to: .quickBolus(enabled: true, incrementUnits: 1000),
            enabled: true,
            incrementUnits: 1000
        )
    }

    func testEnablingAtANewIncrementSendsBothFields() throws {
        try assertSends(
            "0100e803d00705",
            from: .quickBolus(enabled: false, incrementUnits: 500),
            to: .quickBolus(enabled: true, incrementUnits: 1000),
            enabled: true,
            incrementUnits: 1000
        )
    }

    func testChangingToHalfUnit() throws {
        try assertSends(
            "0100f401d00704",
            from: .quickBolus(enabled: true, incrementUnits: 1000),
            to: .quickBolus(enabled: true, incrementUnits: 500),
            enabled: true,
            incrementUnits: 500
        )
    }

    func testChangingToOneUnit() throws {
        try assertSends(
            "0100e803d00704",
            from: .quickBolus(enabled: true, incrementUnits: 500),
            to: .quickBolus(enabled: true, incrementUnits: 1000),
            enabled: true,
            incrementUnits: 1000
        )
    }

    func testChangingToTwoUnits() throws {
        try assertSends(
            "0100d007d00704",
            from: .quickBolus(enabled: true, incrementUnits: 1000),
            to: .quickBolus(enabled: true, incrementUnits: 2000),
            enabled: true,
            incrementUnits: 2000
        )
    }

    func testChangingToFiveUnits() throws {
        try assertSends(
            "01008813d00704",
            from: .quickBolus(enabled: true, incrementUnits: 2000),
            to: .quickBolus(enabled: true, incrementUnits: 5000),
            enabled: true,
            incrementUnits: 5000
        )
    }

    func testDisablingCarriesTheCurrentHalfUnit() throws {
        try assertSends(
            "0000f401d00701",
            from: .quickBolus(enabled: true, incrementUnits: 500),
            to: .quickBolus(enabled: false, incrementUnits: 500),
            enabled: false,
            incrementUnits: 500
        )
    }

    func testDisablingCarriesTheCurrentOneUnit() throws {
        try assertSends(
            "0000e803d00701",
            from: .quickBolus(enabled: true, incrementUnits: 1000),
            to: .quickBolus(enabled: false, incrementUnits: 1000),
            enabled: false,
            incrementUnits: 1000
        )
    }

    func testDisablingCarriesTheCurrentFiveUnits() throws {
        try assertSends(
            "00008813d00701",
            from: .quickBolus(enabled: true, incrementUnits: 5000),
            to: .quickBolus(enabled: false, incrementUnits: 5000),
            enabled: false,
            incrementUnits: 5000
        )
    }

    /// Not captured: the mirror of the captured switch to carbs, `01018813d00702`.
    func testSavingOnACarbsModePumpSwitchesItBackToUnits() throws {
        try assertSends(
            "01008813102702",
            from: .quickBolus(enabled: true, mode: .carbs, incrementUnits: 5000, incrementCarbs: 10000),
            to: .quickBolus(enabled: true, mode: .units, incrementUnits: 5000, incrementCarbs: 10000),
            enabled: true,
            incrementUnits: 5000
        )
    }

    func testAChangeThePumpDidNotApplyFailsTheSave() {
        bluetooth.stub(PumpGlobalsRequest.self, with: PumpGlobalsResponse.quickBolus(enabled: true, mode: .carbs, incrementUnits: 500))

        XCTAssertFalse(set(enabled: true, incrementUnits: 500))
        XCTAssertTrue(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testNothingIsWrittenWhenThePumpAlreadyMatches() {
        bluetooth.stub(PumpGlobalsRequest.self, with: PumpGlobalsResponse.quickBolus(enabled: true, incrementUnits: 2000))

        XCTAssertTrue(set(enabled: true, incrementUnits: 2000))
        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testUnsupportedIncrementIsRefusedWithoutTalkingToThePump() {
        XCTAssertFalse(set(enabled: true, incrementUnits: 750))
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}

extension PumpGlobalsResponse {
    static func quickBolus(
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
}
