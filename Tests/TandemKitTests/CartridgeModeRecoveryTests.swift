import Foundation
@testable import TandemKit
import XCTest

/// The pump refuses `EnterChangeCartridgeMode` while another cartridge procedure is open, and a
/// fill-tubing left open also refuses the change-cartridge exit. Recovery therefore unwinds in the
/// reverse of the wizard's order, lets no refusal stop it, and reports the pump's answer to the
/// final enter.
final class CartridgeModeRecoveryTests: XCTestCase {
    private final class PumpStub {
        private let exitFillTubingStatus: Int?
        private let exitChangeCartridgeStatus: Int?
        private let enterResponse: EnterChangeCartridgeModeResponse?
        private(set) var steps: [String] = []

        init(
            exitFillTubing: Int? = 0,
            exitChangeCartridge: Int? = 0,
            enter: EnterChangeCartridgeModeResponse? = EnterChangeCartridgeModeResponse(status: 0)
        ) {
            exitFillTubingStatus = exitFillTubing
            exitChangeCartridgeStatus = exitChangeCartridge
            enterResponse = enter
        }

        func makeRecovery() -> CartridgeModeRecovery {
            CartridgeModeRecovery(
                exitFillTubing: {
                    self.steps.append("exitFillTubing")
                    return self.exitFillTubingStatus
                },
                exitChangeCartridge: {
                    self.steps.append("exitChangeCartridge")
                    return self.exitChangeCartridgeStatus
                },
                enterChangeCartridge: {
                    self.steps.append("enterChangeCartridge")
                    return self.enterResponse
                }
            )
        }
    }

    func testUnwindsInReverseWizardOrderThenEntersChangeMode() {
        let pump = PumpStub()

        _ = pump.makeRecovery().run()

        XCTAssertEqual(pump.steps, ["exitFillTubing", "exitChangeCartridge", "enterChangeCartridge"])
    }

    func testRefusedExitsDoNotStopTheSequence() {
        let pump = PumpStub(exitFillTubing: 1, exitChangeCartridge: 1)

        let response = pump.makeRecovery().run()

        XCTAssertEqual(pump.steps, ["exitFillTubing", "exitChangeCartridge", "enterChangeCartridge"])
        XCTAssertEqual(response?.status, 0)
    }

    func testUnansweredExitsDoNotStopTheSequence() {
        let pump = PumpStub(exitFillTubing: nil, exitChangeCartridge: nil)

        let response = pump.makeRecovery().run()

        XCTAssertEqual(pump.steps, ["exitFillTubing", "exitChangeCartridge", "enterChangeCartridge"])
        XCTAssertEqual(response?.status, 0)
    }

    func testReturnsThePumpsRefusalOfTheFinalEnter() {
        let pump = PumpStub(enter: EnterChangeCartridgeModeResponse(status: 1))

        XCTAssertEqual(pump.makeRecovery().run()?.status, 1)
    }

    func testReturnsNilWhenThePumpDoesNotAnswerTheFinalEnter() {
        let pump = PumpStub(enter: nil)

        XCTAssertNil(pump.makeRecovery().run())
    }
}

@available(macOS 13.0, iOS 14.0, *) final class RecoverAndReenterChangeCartridgeModeTests: XCTestCase {
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

    private func recover() -> (response: EnterChangeCartridgeModeResponse?, completed: Bool) {
        var result: (response: EnterChangeCartridgeModeResponse?, completed: Bool) = (nil, false)
        manager.recoverAndReenterChangeCartridgeMode { response in
            result = (response, true)
        }
        return result
    }

    private var sentNames: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    func testSendsTheExitsThenTheEnterAndReportsThePumpsAnswer() {
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 1))
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 1))
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        let result = recover()

        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.response?.status, 0)
        XCTAssertEqual(
            sentNames,
            ["ExitFillTubingModeRequest", "ExitChangeCartridgeModeRequest", "EnterChangeCartridgeModeRequest"]
        )
    }

    func testStillEntersWhenThePumpNeverAnswersTheExits() {
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        XCTAssertEqual(recover().response?.status, 0)
        XCTAssertEqual(bluetooth.sent(EnterChangeCartridgeModeRequest.self).count, 1)
    }

    func testSendsNothingWhenThePumpCannotBeReached() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let result = recover()

        XCTAssertTrue(result.completed)
        XCTAssertNil(result.response)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
