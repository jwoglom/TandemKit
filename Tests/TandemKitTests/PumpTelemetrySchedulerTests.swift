import XCTest
@testable import TandemKit

final class PumpTelemetrySchedulerTests: XCTestCase {
    func testTriggerAllExecutesHandlersImmediately() {
        let scheduler = PumpTelemetryScheduler(label: "com.jwoglom.TandemKit.tests.telemetry")
        let expectation = expectation(description: "reservoir handler executed")

        scheduler.schedule(kind: .reservoir, interval: 60) {
            expectation.fulfill()
        }

        scheduler.triggerAll()

        waitForExpectations(timeout: 1.0)
        scheduler.cancelAll()
    }

    func testTriggerSingleKind() {
        let scheduler = PumpTelemetryScheduler(label: "com.jwoglom.TandemKit.tests.telemetry.single")
        let reservoirExpectation = expectation(description: "reservoir handler executed")
        reservoirExpectation.isInverted = true
        let batteryExpectation = expectation(description: "battery handler executed")

        scheduler.schedule(kind: .reservoir, interval: 60) {
            reservoirExpectation.fulfill()
        }

        scheduler.schedule(kind: .battery, interval: 60) {
            batteryExpectation.fulfill()
        }

        scheduler.trigger(kind: .battery)

        wait(for: [reservoirExpectation, batteryExpectation], timeout: 1.0)
        scheduler.cancelAll()
    }
}
