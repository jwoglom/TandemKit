@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The response timeout runs on the wall clock (#506). A real sleep can't be induced here, so these
/// pin the elapsed real time of the timeout, and that a delayed or late response is handled by it.
final class ResponseTimeoutIntegrationTests: FaketandemIntegrationTestCase {
    private func writeApiVersion(_ driver: FaketandemHarness.Driver) -> (response: ApiVersionResponse?, elapsed: TimeInterval) {
        let done = expectation(description: "write returns")
        var response: ApiVersionResponse?
        let started = Date()
        driver.bluetooth.ensureConnected { error in
            if error == nil { response = driver.bluetooth.write(ApiVersionRequest()) }
            done.fulfill()
        }
        wait(for: [done], timeout: FaketandemHarness.responseTimeout + 30)
        return (response, Date().timeIntervalSince(started))
    }

    func testADroppedResponseFailsAfterTheResponseTimeoutInRealTime() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        try harness.client.armFault(FaketandemFaultSpec(.dropResponse, message: "ApiVersionRequest"))

        let (response, elapsed) = writeApiVersion(driver)

        XCTAssertNil(response)
        XCTAssertGreaterThanOrEqual(elapsed, FaketandemHarness.responseTimeout - 0.5, "failed early: \(elapsed)s")
        XCTAssertLessThan(elapsed, FaketandemHarness.responseTimeout + 5, "failed late: \(elapsed)s")
    }

    func testAResponseDelayedWithinTheTimeoutIsStillDelivered() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        var fault = FaketandemFaultSpec(.delayResponse, message: "ApiVersionRequest")
        fault.delayMilliseconds = Int(FaketandemHarness.responseTimeout * 1000 / 2)
        try harness.client.armFault(fault)

        let (response, elapsed) = writeApiVersion(driver)

        XCTAssertNotNil(response)
        XCTAssertGreaterThanOrEqual(elapsed, FaketandemHarness.responseTimeout / 2 - 0.5)
        XCTAssertLessThan(elapsed, FaketandemHarness.responseTimeout)
    }

    func testTheSessionServesCommandsAfterATimeout() throws {
        let driver = makeDriver()
        try harness.pair(driver)
        try harness.client.armFault(FaketandemFaultSpec(.dropResponse, message: "ApiVersionRequest"))
        XCTAssertNil(writeApiVersion(driver).response)

        XCTAssertNotNil(writeApiVersion(driver).response, "the fault was one-shot; the next command must be answered")
        XCTAssertNotNil(try harness.sync(driver))
    }
}
