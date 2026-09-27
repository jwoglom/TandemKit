import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The same flows the other classes run, but with the link's ATT MTU moved.
///
/// faketandem defaults to the 23-byte Bluetooth minimum, so every response arrives as a run of
/// 20-byte notifications carrying 18 message bytes each — pumpX2's framing, and what exposed the
/// two reassembly bugs in `TandemPeripheralManager` / `BTResponseParser`. A real Mobi paired with
/// the official iOS app negotiates a much larger MTU and most responses arrive whole, in one
/// notification with `remaining = 0`. `BTResponseParser` keys off the remaining counter and never a
/// fragment's length, so both must work; these tests hold it to that on real traffic.
final class MTUIntegrationTests: FaketandemIntegrationTestCase {
    private static let units = 1.0
    private static let deliveryRate = 0.25

    /// `setUpWithError` resets the emulator, which restores the default; this puts it back after a
    /// test that raised it, so a crash here cannot change the framing another class sees.
    override func tearDownWithError() throws {
        if let harness {
            try? harness.client.setATTMTU(FaketandemClient.defaultATTMTU)
        }
        try super.tearDownWithError()
    }

    /// One response as the pump logged it: its message bytes, and how many notifications carried them.
    private struct Response {
        let message: String
        let bodyBytes: Int
        let fragmentsSent: Int
    }

    private func responses(since: Int? = nil) throws -> [Response] {
        try harness.requestLog(since: since).filter(\.isResponse).compactMap { entry in
            guard let fragments = entry.fragments, !fragments.isEmpty else { return nil }
            // Each fragment is hex; the first two bytes are [remainingPackets][txId] framing.
            let body = fragments.reduce(0) { $0 + max(0, $1.count / 2 - 2) }
            return Response(message: entry.message ?? "?", bodyBytes: body, fragmentsSent: fragments.count)
        }
    }

    private func enactBolus(_ driver: FaketandemHarness.Driver) throws -> PumpManagerError? {
        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactBolus(units: Self.units, activationType: .manualNoRecommendation) { box.set($0) }
        return try box.wait("enactBolus completion", timeout: 60)
    }

    /// Pair, sync and bolus with an MTU that fits a whole response: the driver must cope with
    /// unfragmented notifications, and every response that fits must actually arrive as one.
    func testLargeMTUDeliversWholeResponsesAndTheFlowStillRuns() throws {
        let transport = try harness.client.setATTMTU(FaketandemClient.largeATTMTU)
        XCTAssertEqual(transport.attMtu, FaketandemClient.largeATTMTU)
        XCTAssertTrue(transport.mtuConfigurable, "the virtual transport must expose its MTU")
        let capacity = transport.maxMessageBytesPerNotification
        XCTAssertGreaterThan(capacity, FaketandemClient.defaultATTMTU, "a large MTU must carry more than the floor")

        let clock = ManualClock(Date())
        let driver = makeDriver(clock: clock)
        try harness.pair(driver)
        // .5 so the truncation to whole units is stable while the simulator drains basal; see
        // SyncIntegrationTests.
        try harness.client.setState(["reservoir_units": 137.5, "battery_percent": 64])

        let lastSync = try harness.sync(driver)
        XCTAssertNotNil(lastSync, "sync must succeed at a large MTU")
        XCTAssertEqual(driver.delegate.reservoirReadings.last?.units, 137)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "no communication errors: \(driver.delegate.errors)")

        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate])
        let bolusLogStart = try harness.client.snapshot().requestLog.lastSeq
        let error = try enactBolus(driver)
        XCTAssertNil(error, "enactBolus failed at a large MTU: \(String(describing: error))")
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let control = try harness.requestsSeen(since: bolusLogStart).filter { $0.characteristic == "Control" }
        XCTAssertEqual(
            control.prefix(2).map(\.opcode),
            [Int(BolusPermissionRequest.props.opCode), Int(InitiateBolusRequest.props.opCode)],
            "BolusPermission then InitiateBolus: \(control)"
        )
        XCTAssertEqual(try harness.client.snapshot().bolus.bolusId, bolusId)

        // The framing the pump actually used across the whole session.
        let seen = try responses()
        XCTAssertFalse(seen.isEmpty, "the pump answered nothing")
        let split = seen.filter { $0.bodyBytes <= capacity && $0.fragmentsSent != 1 }
        XCTAssertTrue(
            split.isEmpty,
            "a response that fits in one \(capacity)-byte notification must not be fragmented: \(split)"
        )
        XCTAssertTrue(
            seen.contains { $0.fragmentsSent == 1 && $0.bodyBytes > FaketandemClient.defaultATTMTU - 5 },
            "nothing arrived whole that the default MTU would have split, so the MTU never took effect: \(seen)"
        )
    }

    /// The contrast, on the same traffic: at the default MTU the pump splits anything over 18 bytes
    /// and the driver reassembles it. This is the framing every other integration test runs under.
    func testDefaultMTUFragmentsTheSameResponses() throws {
        let transport = try harness.client.transport()
        XCTAssertEqual(transport.attMtu, FaketandemClient.defaultATTMTU, "reset must leave the default MTU")
        XCTAssertEqual(transport.maxMessageBytesPerNotification, 18, "20-byte notifications, 18 of message")

        let driver = makeDriver()
        try harness.pair(driver)
        XCTAssertNotNil(try harness.sync(driver))
        XCTAssertTrue(driver.delegate.errors.isEmpty, "no communication errors: \(driver.delegate.errors)")

        let seen = try responses()
        XCTAssertFalse(seen.isEmpty, "the pump answered nothing")
        XCTAssertTrue(
            seen.contains { $0.fragmentsSent > 1 },
            "the default MTU must fragment; the driver's reassembler is what this exercises: \(seen)"
        )
        let wrong = seen.filter { $0.fragmentsSent != max(1, Int(ceil(Double($0.bodyBytes) / 18.0))) }
        XCTAssertTrue(wrong.isEmpty, "every response must be cut into 18-byte chunks: \(wrong)")
    }
}
