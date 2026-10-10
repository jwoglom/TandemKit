import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Trio's own DeviceDataManager and pump history against TrioDoseStoreOracle, the model of them the
/// conformance tests use: fed the batches the driver gave Trio, the oracle must predict the rows
/// Trio stored.
final class TrioBolusTests: FaketandemIntegrationTestCase {
    private var trio: TrioApp!
    private var control: VirtualPumpControl.Client?

    override func setUpWithError() throws {
        try super.setUpWithError()
        trio = try TrioApp.fromEnvironment()
        control = try trio.connectControl()
    }

    override func tearDownWithError() throws {
        control?.close()
        try super.tearDownWithError()
    }

    func testAnAppBolusIsStoredByTrioAsTheOracleExpects() throws {
        let control = try XCTUnwrap(control)
        var key = Data(count: 32)
        for index in key.indices {
            key[index] = UInt8.random(in: .min ... .max)
        }
        _ = try harness.control.setLongTermKey(key)
        let paired = try control.send(.init(command: .pair, code: FaketandemHarness.pairingCode, longTermKey: key.hexadecimalString))
        XCTAssertEqual(paired.status?.onboarded, true)
        XCTAssertEqual(paired.status?.delegateAttached, true, "Trio's DeviceDataManager must be the driver's delegate")
        try control.send(.init(command: .sync))
        try harness.client.setState(["bolus_rate_units_per_second": 0.25])

        try control.send(.init(command: .bolus, units: 1.0))

        // Trio calls a batch's completion once it has saved it, so a completed log is all in the store.
        let batches = try IntegrationWait.value("Trio to have stored a finalized bolus", timeout: 300) { () -> [VirtualPumpControl.Batch]? in
            try control.send(.init(command: .sync))
            let batches = try XCTUnwrap(control.send(.init(command: .pumpEventBatches)).batches)
            let finalized = batches.flatMap(\.pumpEvents).contains { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
            return finalized && batches.allSatisfy(\.completed) ? batches : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Trio failed to store a batch")

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

        assertSameRows(stored, oracle.events.map(TrioStoredPumpEvent.init))
        let boluses = stored.filter { $0.type == TrioDoseStoreOracle.EventType.bolus.rawValue }
        XCTAssertEqual(boluses.count, 1, "one bolus row: \(boluses)")
        XCTAssertEqual(boluses.first?.isMutable, false)
        XCTAssertEqual(boluses.first?.bolusAmount ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(boluses.first?.isSMB, false)
    }

    /// Row for row, in timestamp order. Trio dates a row `min(event.date, now)` with its own now at
    /// saving, the oracle with the driver's at sending, so timestamps agree to a second or two.
    private func assertSameRows(
        _ stored: [TrioStoredPumpEvent],
        _ predicted: [TrioStoredPumpEvent],
        file: StaticString = #filePath,
        line: UInt = #line
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
}
