import Foundation
@testable import TandemKit
import XCTest

/// Base for every test against the emulator: skips without the environment, resets the pump before
/// each test, tears the driver down after it, and attaches the pump-side request log to a failure.
class FaketandemIntegrationTestCase: XCTestCase {
    var harness: FaketandemHarness!
    private(set) var driver: FaketandemHarness.Driver?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        harness = try FaketandemHarness.fromEnvironment()
        try harness.reset()
    }

    override func tearDownWithError() throws {
        if let harness {
            attachRequestLog()
            if let driver {
                do {
                    try harness.shutDown(driver)
                } catch {
                    XCTFail("driver shutdown failed: \(error)")
                }
            }
        }
        driver = nil
        harness = nil
        try super.tearDownWithError()
    }

    func makeDriver(
        state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:]),
        clock: TandemClock = ManualClock(Date())
    ) -> FaketandemHarness.Driver {
        precondition(driver == nil, "one driver per test; shut the previous one down first")
        let created = harness.makeDriver(state: state, clock: clock)
        driver = created
        return created
    }

    /// Ends the current driver so a second one (a relaunch) can attach to the pump.
    func shutDownDriver() throws {
        guard let driver else { return }
        try harness.shutDown(driver)
        self.driver = nil
    }

    private func attachRequestLog() {
        guard let entries = try? harness.requestLog() else { return }
        let lines = entries.map { entry -> String in
            var line = "\(entry.seq) \(entry.kind)"
            if let characteristic = entry.characteristic { line += " \(characteristic)" }
            if let opcode = entry.opcode { line += " op=\(opcode)" }
            if let message = entry.message { line += " \(message)" }
            if let connected = entry.connected { line += " connected=\(connected)" }
            if let fault = entry.fault { line += " fault=\(fault)" }
            if let note = entry.note { line += " note=\(note)" }
            if let fragments = entry.fragments { line += " \(fragments.joined(separator: "|"))" }
            return line
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "faketandem-request-log.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
