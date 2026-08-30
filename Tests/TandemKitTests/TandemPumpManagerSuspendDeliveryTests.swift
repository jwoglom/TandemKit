import LoopKit
@testable import TandemKit
import XCTest

/// Covers the command sequence `suspendDelivery` sends, and what it does with the outcome of
/// cancelling a running temp rate.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerSuspendDeliveryTests: XCTestCase {
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

    // MARK: - Helpers

    private func stubTempRate(active: Bool) {
        bluetooth.stub(TempRateRequest.self, with: TempRateResponse(
            active: active,
            percentage: active ? 150 : 0,
            startTimeRaw: 0,
            duration: active ? 1800 : 0
        ))
    }

    private func suspend() -> Error? {
        var result: Error?
        let expectation = expectation(description: "suspendDelivery")
        manager.suspendDelivery {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private var sentTypes: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    // MARK: - Tests

    func testSuspendWithRunningTempRateStopsItThenSuspends() {
        stubTempRate(active: true)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 1107))
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))

        XCTAssertNil(suspend())

        XCTAssertEqual(sentTypes, ["TempRateRequest", "StopTempRateRequest", "SuspendPumpingRequest"])
    }

    func testSuspendWithoutARunningTempRateSkipsTheStop() {
        stubTempRate(active: false)
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))

        XCTAssertNil(suspend())

        XCTAssertEqual(sentTypes, ["TempRateRequest", "SuspendPumpingRequest"])
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
    }

    func testSuspendStillGoesOutWhenTheTempRateStopIsRefused() {
        stubTempRate(active: true)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 1, tempRateId: 1107))
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))

        XCTAssertNil(suspend())

        XCTAssertTrue(bluetooth.didSend(SuspendPumpingRequest.self))
    }

    func testSuspendStillGoesOutWhenTheTempRateStopIsUnanswered() {
        stubTempRate(active: true)
        bluetooth.stub(StopTempRateRequest.self) { _ in nil }
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))

        XCTAssertNil(suspend())

        XCTAssertTrue(bluetooth.didSend(SuspendPumpingRequest.self))
    }

    func testSuspendReportsAPumpRejection() {
        stubTempRate(active: false)
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 1))

        XCTAssertNotNil(suspend())
    }

    func testSuspendRecordsASuspendDose() {
        stubTempRate(active: false)
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))

        XCTAssertNil(suspend())

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
    }
}
