@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class PumpSoundSettingsTests: XCTestCase {
    private let beep = PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue
    private let vibrate = PumpGlobalsResponse.AnnunciationEnum.vibrate.rawValue

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

    private func setGeneralSoundToBeep() -> Bool {
        let request = SetPumpSoundsRequest(
            quickBolusAnnunRaw: vibrate,
            generalAnnunRaw: beep,
            reminderAnnunRaw: vibrate,
            alertAnnunRaw: vibrate,
            alarmAnnunRaw: vibrate,
            cgmAlertAnnunA: 0,
            cgmAlertAnnunB: 0,
            changeBitmaskRaw: PumpSoundChangeBitmask.generalAnnun.rawValue
        )
        let done = expectation(description: "setPumpSound")
        var accepted = false
        manager.setPumpSound(request: request) {
            accepted = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return accepted
    }

    private func stubPumpReportsGeneralSound(_ general: Int) {
        bluetooth.stub(
            PumpGlobalsRequest.self,
            with: PumpGlobalsResponse(
                quickBolusEnabledRaw: 0,
                quickBolusIncrementUnits: 500,
                quickBolusIncrementCarbs: 2000,
                quickBolusEntryType: QuickBolusMode.units.rawValue,
                quickBolusStatus: 0,
                buttonAnnun: 0,
                quickBolusAnnun: vibrate,
                generalAnnun: general,
                reminderAnnun: vibrate,
                alertAnnun: vibrate,
                alarmAnnun: vibrate,
                fillTubingAnnun: 0
            )
        )
    }

    func testAnAcceptedChangeSucceedsAndReadsBackThePumpsSounds() throws {
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 0))
        stubPumpReportsGeneralSound(beep)

        XCTAssertTrue(setGeneralSoundToBeep())
        XCTAssertEqual(try XCTUnwrap(bluetooth.sent(SetPumpSoundsRequest.self).first).generalAnnunRaw, beep)
        XCTAssertEqual(manager.state.generalAnnun, .audioHigh)
    }

    func testARefusedChangeFailsAndReadsBackThePumpsSounds() {
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        stubPumpReportsGeneralSound(vibrate)

        XCTAssertFalse(setGeneralSoundToBeep())
        XCTAssertEqual(manager.state.generalAnnun, .vibrate)
    }

    func testAnUnansweredChangeFailsAndReadsBackThePumpsSounds() {
        bluetooth.stub(SetPumpSoundsRequest.self) { _ in nil }
        stubPumpReportsGeneralSound(vibrate)

        XCTAssertFalse(setGeneralSoundToBeep())
        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertEqual(manager.state.generalAnnun, .vibrate)
    }

    func testAChangeWithNoConnectionFailsAndSendsNothing() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        XCTAssertFalse(setGeneralSoundToBeep())
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
