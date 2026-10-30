@testable import TandemKit
import XCTest

/// Cargo from pumpX2's `LoadStatusResponseTest`, which has no framed vector; the framing is built here.
final class LoadStatusResponseTests: XCTestCase {
    func testLoadStatusResponseChangeCartridgeInProgress() {
        let expected = LoadStatusResponse(isLoadingActive: true, loadStateId: 0, primeStatusId: 0)

        let parsed: LoadStatusResponse = MessageTester.test(
            "00041504030100007f72",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertTrue(parsed.isLoadingActive)
        XCTAssertEqual(parsed.loadState, .changeCartridge)
        XCTAssertNil(parsed.primeTubingStatus)
    }

    func testLoadStatusResponseCartridgeChanged() {
        let expected = LoadStatusResponse(isLoadingActive: true, loadStateId: 1, primeStatusId: 0)

        let parsed: LoadStatusResponse = MessageTester.test(
            "00041504030101004e41",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertTrue(parsed.isLoadingActive)
        XCTAssertEqual(parsed.loadState, .loadCartridge)
    }

    func testLoadStatusResponsePrimeTubing() {
        let parsed = LoadStatusResponse(cargo: Data([1, 2, 3]))

        XCTAssertEqual(parsed.loadState, .primeTubing)
        XCTAssertEqual(parsed.primeTubingStatus, .enteredCannotExit)
        XCTAssertNil(parsed.primeNudgeStatus)
    }

    func testLoadStatusResponseFillTubingComplete() {
        let parsed = LoadStatusResponse(cargo: Data([0, 4, 1]))

        XCTAssertFalse(parsed.isLoadingActive)
        XCTAssertEqual(parsed.loadState, .primeNudge)
        XCTAssertEqual(parsed.primeNudgeStatus, .complete)
        XCTAssertFalse(parsed.isInLoadingState)
    }
}
