@testable import TandemKit
import XCTest

/// A cartridge wizard abandoned mid-fill leaves the pump in fill-tubing mode, where it refuses to
/// enter change-cartridge mode and refuses the exit a driver sends to back out. The emulator refuses
/// the same way (`workflow_mode`), which is inferred from a field report rather than confirmed on
/// firmware, so these tests pin the driver's recovery against that model.
final class CartridgeProcedureIntegrationTests: FaketandemIntegrationTestCase {
    private static let procedureRequests: Set<String> = [
        "EnterChangeCartridgeModeRequest", "ExitChangeCartridgeModeRequest",
        "EnterFillTubingModeRequest", "ExitFillTubingModeRequest"
    ]

    private func pairedSuspendedDriver() throws -> FaketandemHarness.Driver {
        let driver = makeDriver()
        try harness.pair(driver)
        try harness.client.setState(["suspended": true])
        return driver
    }

    private func status<Response>(
        _ what: String,
        _ start: (@escaping (Response?) -> Void) -> Void,
        _ read: @escaping (Response) -> Int
    ) throws -> Int? {
        let box = ResultBox<Int?>()
        start { box.set($0.map(read)) }
        return try box.wait(what, timeout: 30)
    }

    private func enterFillTubing(_ driver: FaketandemHarness.Driver) throws -> Int? {
        try status("EnterFillTubingMode", driver.manager.enterFillTubingMode) { $0.status }
    }

    private func enterChangeCartridge(_ driver: FaketandemHarness.Driver) throws -> Int? {
        try status("EnterChangeCartridgeMode", driver.manager.enterChangeCartridgeMode) { $0.status }
    }

    private func exitChangeCartridge(_ driver: FaketandemHarness.Driver) throws -> Int? {
        try status("ExitChangeCartridgeMode", driver.manager.exitChangeCartridgeMode) { $0.status }
    }

    private func recover(_ driver: FaketandemHarness.Driver) throws -> Int? {
        try status("recoverAndReenterChangeCartridgeMode", driver.manager.recoverAndReenterChangeCartridgeMode) { $0.status }
    }

    private func workflowMode() throws -> String? {
        try harness.client.snapshot().workflowMode
    }

    private func procedureRequestsSeen() throws -> [String] {
        try harness.requestsSeen().map(\.message).filter(Self.procedureRequests.contains)
    }

    func testAnAbandonedFillTubingRefusesChangeModeAndItsExit() throws {
        let driver = try pairedSuspendedDriver()

        XCTAssertEqual(try enterFillTubing(driver), 0)
        XCTAssertEqual(try workflowMode(), "fill_tubing")

        XCTAssertEqual(try enterChangeCartridge(driver), 1, "the pump refuses while fill tubing is open")
        XCTAssertEqual(try exitChangeCartridge(driver), 1, "backing out of change mode does not help: the pump is not in it")
        XCTAssertEqual(try workflowMode(), "fill_tubing")
    }

    func testRecoveryUnwindsAnAbandonedFillTubingAndEntersChangeMode() throws {
        let driver = try pairedSuspendedDriver()
        XCTAssertEqual(try enterFillTubing(driver), 0)
        XCTAssertEqual(try enterChangeCartridge(driver), 1)

        XCTAssertEqual(try recover(driver), 0)

        XCTAssertEqual(try workflowMode(), "change_cartridge")
        XCTAssertEqual(
            try procedureRequestsSeen().suffix(3),
            ["ExitFillTubingModeRequest", "ExitChangeCartridgeModeRequest", "EnterChangeCartridgeModeRequest"],
            "the pump must see the exits in the reverse of the wizard's order, then the enter"
        )
    }

    func testRecoveryUnwindsAChangeModeLeftOpen() throws {
        let driver = try pairedSuspendedDriver()
        XCTAssertEqual(try enterChangeCartridge(driver), 0)
        XCTAssertEqual(try enterChangeCartridge(driver), 1, "already in change mode")

        XCTAssertEqual(try recover(driver), 0)

        XCTAssertEqual(try workflowMode(), "change_cartridge")
    }

    func testRecoveryOnAnIdlePumpJustEntersChangeMode() throws {
        let driver = try pairedSuspendedDriver()

        XCTAssertEqual(try recover(driver), 0)

        XCTAssertEqual(try workflowMode(), "change_cartridge")
    }

    func testRecoveryDoesNotEnterChangeModeWhileDeliveryIsRunning() throws {
        let driver = makeDriver()
        try harness.pair(driver)

        XCTAssertEqual(try recover(driver), 1)

        XCTAssertEqual(try workflowMode(), "none")
    }

    func testAChangeCartridgeAfterRecoveryCanBeCompletedNormally() throws {
        let driver = try pairedSuspendedDriver()
        XCTAssertEqual(try enterFillTubing(driver), 0)
        XCTAssertEqual(try recover(driver), 0)

        XCTAssertEqual(try exitChangeCartridge(driver), 0)

        XCTAssertEqual(try workflowMode(), "none")
        XCTAssertEqual(try enterFillTubing(driver), 0, "the wizard's next step is accepted")
    }
}
