import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Each test gets a new install of Trio, on a reset faketandem. What Trio stored is compared with
/// TrioDoseStoreOracle, the model of Trio's DeviceDataManager and pump history the conformance tests
/// use: fed the batches the driver gave Trio, the oracle must predict the rows Trio stored.
class TrioTestCase: FaketandemIntegrationTestCase {
    private(set) var trio: TrioApp!
    private(set) var control: VirtualPumpControl.Client!
    /// Batches the driver gave Trio before a relaunch; each launch's driver logs from scratch.
    private var earlierLaunchesBatches: [VirtualPumpControl.Batch] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        trio = try TrioApp.launchFresh(name: name)
        control = try trio.connectControl()
    }

    override func tearDownWithError() throws {
        control?.close()
        control = nil
        do {
            try trio?.stop()
        } catch {
            XCTFail("stopping Trio failed: \(error)")
        }
        trio = nil
        try super.tearDownWithError()
    }

    /// Pairs the driver inside Trio with faketandem on a key given to both, as a returning pairing
    /// does, and syncs.
    func pairTrio() throws {
        var key = Data(count: 32)
        for index in key.indices {
            key[index] = UInt8.random(in: .min ... .max)
        }
        _ = try harness.control.setLongTermKey(key)
        let paired = try control.send(.init(command: .pair, code: FaketandemHarness.pairingCode, longTermKey: key.hexadecimalString))
        XCTAssertEqual(paired.status?.onboarded, true)
        XCTAssertEqual(paired.status?.delegateAttached, true, "Trio's DeviceDataManager must be the driver's delegate")
        try control.send(.init(command: .sync))
    }

    /// One segment at `unitsPerHour`, as seeded into Trio's own basal profile.
    func syncBasalSchedule(unitsPerHour: Double = 1.0) throws {
        try control.send(.init(command: .syncBasalSchedule, basalSchedule: [RepeatingScheduleValue(startTime: 0, value: unitsPerHour)]))
    }

    /// Stops Trio and starts it again on the same data once it has stored everything it was given.
    func relaunchTrio() throws {
        earlierLaunchesBatches = try trioStored("every batch before the relaunch") { _ in true }
        control.close()
        trio = try trio.relaunched()
        control = try trio.connectControl()
    }

    /// Every batch the driver gave Trio, once `condition` holds of their events and Trio has stored
    /// them all (Trio calls a batch's completion once it has saved it). With `syncing`, syncs before
    /// each look, as the host does before it doses.
    @discardableResult
    func trioStored(
        _ what: String,
        syncing: Bool = false,
        timeout: TimeInterval = 300,
        until condition: @escaping ([NewPumpEvent]) -> Bool
    ) throws -> [VirtualPumpControl.Batch] {
        let control = try XCTUnwrap(control)
        let earlier = earlierLaunchesBatches
        let batches = try IntegrationWait.value("Trio to have stored \(what)", timeout: timeout) { () -> [VirtualPumpControl.Batch]? in
            if syncing {
                try control.send(.init(command: .sync))
            }
            let batches = try earlier + XCTUnwrap(control.send(.init(command: .pumpEventBatches)).batches)
            return condition(batches.flatMap(\.pumpEvents)) && batches.allSatisfy(\.completed) ? batches : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Trio failed to store a batch")
        return batches
    }

    /// Feeds `batches` to the oracle and checks Trio stored the rows it predicts; returns both.
    @discardableResult
    func assertTrioStoredWhatTheOracleExpects(
        _ batches: [VirtualPumpControl.Batch],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (stored: [TrioStoredPumpEvent], oracle: TrioDoseStoreOracle) {
        let oracle = try TrioDoseStoreOracle(maxBasal: trio.maxBasal(), bolusIncrement: trio.bolusIncrement())
        for batch in batches {
            oracle.addPumpEvents(
                batch.pumpEvents,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: batch.hostNow
            )
        }
        let stored = try trio.store().pumpEvents()
        assertSameRows(stored, oracle.events.map(TrioStoredPumpEvent.init), file: file, line: line)
        return (stored, oracle)
    }

    /// Row for row, in timestamp order. Trio dates a row `min(event.date, now)` with its own now at
    /// saving, the oracle with the driver's at sending, so timestamps agree to a second or two.
    private func assertSameRows(
        _ stored: [TrioStoredPumpEvent],
        _ predicted: [TrioStoredPumpEvent],
        file: StaticString,
        line: UInt
    ) {
        let order: (TrioStoredPumpEvent, TrioStoredPumpEvent) -> Bool = {
            ($0.timestamp, $0.syncIdentifier ?? "") < ($1.timestamp, $1.syncIdentifier ?? "")
        }
        let stored = stored.sorted(by: order)
        let predicted = predicted.sorted(by: order)
        let report = "Trio stored:\n\(stored.map { "  \($0)" }.joined(separator: "\n"))\noracle predicted:\n\(predicted.map { "  \($0)" }.joined(separator: "\n"))"
        guard stored.count == predicted.count else {
            return XCTFail("row counts differ\n\(report)", file: file, line: line)
        }
        for (actual, expected) in zip(stored, predicted) {
            var expected = expected
            if abs(actual.timestamp.timeIntervalSince(expected.timestamp)) <= 2 {
                expected.timestamp = actual.timestamp
            }
            for keyPath in [\TrioStoredPumpEvent.bolusAmount, \.programmedAmount, \.tempBasalRate] {
                if let a = actual[keyPath: keyPath], let e = expected[keyPath: keyPath], abs(a - e) < 1e-6 {
                    expected[keyPath: keyPath] = a
                }
            }
            XCTAssertEqual(actual, expected, report, file: file, line: line)
        }
    }
}

extension TrioStoredPumpEvent {
    init(_ row: TrioDoseStoreOracle.StoredEvent) {
        let double = { (value: Decimal?) in value.map { NSDecimalNumber(decimal: $0).doubleValue } }
        self.init(
            timestamp: row.timestamp,
            type: row.type.rawValue,
            syncIdentifier: row.syncIdentifier,
            isMutable: row.isMutable,
            bolusAmount: double(row.bolusAmount),
            programmedAmount: double(row.programmedAmount),
            isSMB: row.isSMB,
            isExternal: row.isExternal,
            tempBasalRate: double(row.tempBasalRate),
            tempBasalDurationMinutes: row.tempBasalDurationMinutes,
            isScheduledBasal: row.type == .tempBasal ? row.isScheduledBasal : nil
        )
    }

    var isTempBasal: Bool {
        type == TrioDoseStoreOracle.EventType.tempBasal.rawValue && isScheduledBasal == false
    }
}
