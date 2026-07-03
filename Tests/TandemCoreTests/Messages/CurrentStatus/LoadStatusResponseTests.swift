@testable import TandemCore
import XCTest

final class LoadStatusResponseTests: XCTestCase {
    // MARK: - Parsing

    func testParsesThreeByteCargo() {
        // isLoadingActive=1, loadState=primeTubing(2), primeTubingStatus=enteredCanExit(2)
        let response = LoadStatusResponse(cargo: Data([0x01, 0x02, 0x02]))

        XCTAssertTrue(response.isLoadingActive)
        XCTAssertEqual(response.loadState, .primeTubing)
        XCTAssertEqual(response.primeTubingStatus, .enteredCanExit)
        XCTAssertNil(response.primeNudgeStatus)
    }

    func testPrimeTubingStatusIsNilUnlessPrimeTubing() {
        // loadState=loadCartridge(1): primeTubingStatus must be nil even though cargo[2] is populated.
        let response = LoadStatusResponse(cargo: Data([0x01, 0x01, 0x02]))

        XCTAssertEqual(response.loadState, .loadCartridge)
        XCTAssertNil(response.primeTubingStatus)
    }

    func testUnknownLoadStateFallsBack() {
        // 0x63 (99) is out of the LoadState range → .unknown
        let response = LoadStatusResponse(cargo: Data([0x00, 0x63, 0x00]))

        XCTAssertFalse(response.isLoadingActive)
        XCTAssertEqual(response.loadState, .unknown)
    }

    // MARK: - isInTubingFillMode predicate (drives fill-tubing auto-exit detection)

    func testIsInTubingFillModeTrueForAnyPrimeTubingSubStatus() {
        // Keyed off loadState alone: while in primeTubing, a released button (e.g. .stop) must NOT
        // read as "exited", otherwise Continue-filling would pop after every button release.
        for status in 0 ... 5 {
            let response = LoadStatusResponse(
                isLoadingActive: false,
                loadStateId: LoadStatusResponse.LoadState.primeTubing.rawValue,
                primeStatusId: status
            )
            XCTAssertTrue(
                response.isInTubingFillMode,
                "primeTubing with primeTubingStatus \(status) should be considered in fill mode"
            )
        }
    }

    func testIsInTubingFillModeFalseWhenNotPrimeTubing() {
        let nonFillStates: [LoadStatusResponse.LoadState] = [
            .changeCartridge, .loadCartridge, .primeCannula, .primeNudge, .invalid, .unknown
        ]
        for state in nonFillStates {
            let response = LoadStatusResponse(
                isLoadingActive: true,
                loadStateId: state.rawValue,
                primeStatusId: 0
            )
            XCTAssertFalse(response.isInTubingFillMode, "\(state) should not be considered in fill mode")
        }
    }

    // MARK: - Message metadata

    func testRequestMetadata() {
        XCTAssertEqual(LoadStatusRequest.props.opCode, 20)
        XCTAssertEqual(LoadStatusRequest.props.size, 0)
        XCTAssertTrue(LoadStatusRequest().cargo.isEmpty)
    }

    func testResponseMetadata() {
        XCTAssertEqual(LoadStatusResponse.props.opCode, 21)
        XCTAssertEqual(LoadStatusResponse.props.size, 3)
    }
}
