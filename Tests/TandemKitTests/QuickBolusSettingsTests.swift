@testable import TandemKit
import XCTest

/// #428
@available(macOS 13.0, iOS 14.0, *) final class QuickBolusSettingsTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func set(enabled: Bool, increment: QuickBolusIncrement) -> Bool {
        let done = expectation(description: "setQuickBolusSettings")
        var result = false
        manager.setQuickBolusSettings(enabled: enabled, increment: increment) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    func testCarbsIncrementsAreRefusedWithoutWritingToThePump() {
        for increment in [QuickBolusIncrement.carbs2g, .carbs5g, .carbs10g, .carbs15g] {
            XCTAssertFalse(set(enabled: true, increment: increment), "\(increment)")
        }
        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testUnitsIncrementIsWrittenInUnitsMode() throws {
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 0))

        XCTAssertTrue(set(enabled: true, increment: .units1_0))

        let request = try XCTUnwrap(bluetooth.sent(SetQuickBolusSettingsRequest.self).first)
        XCTAssertEqual(request.mode, .units)
        XCTAssertEqual(request.increment, .units1_0)
    }
}
