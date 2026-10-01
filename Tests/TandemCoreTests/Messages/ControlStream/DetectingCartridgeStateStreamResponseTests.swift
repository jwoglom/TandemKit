@testable import TandemKit
import XCTest

final class DetectingCartridgeStateStreamResponseTests: XCTestCase {
    func testDetectingCartridgeStateStreamResponse_1() {
        let expected = DetectingCartridgeStateStreamResponse(cargo: Data([20, 0]))

        let parsed: DetectingCartridgeStateStreamResponse = MessageTester.test(
            "0089e3891a140078c84020f4eabab90ec17db0da1b4d99095f92c063a1b1b9456a",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(20, parsed.percentComplete)
        XCTAssertEqual(20, parsed.stateId)
        XCTAssertFalse(parsed.loadCartridgeState)
    }

    func testDetectingCartridgeStateStreamResponse_2() {
        let expected = DetectingCartridgeStateStreamResponse(cargo: Data([40, 0]))

        let parsed: DetectingCartridgeStateStreamResponse = MessageTester.test(
            "0089e3891a280078c840207ae3354ae4a861ca6cbaf2a6acc178441f68714f8a3f",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(40, parsed.percentComplete)
        XCTAssertEqual(40, parsed.stateId)
        XCTAssertFalse(parsed.loadCartridgeState)
    }

    func testDetectingCartridgeStateStreamResponse_3() {
        let expected = DetectingCartridgeStateStreamResponse(cargo: Data([60, 0]))

        let parsed: DetectingCartridgeStateStreamResponse = MessageTester.test(
            "0089e3891a3c0078c840204b662d159bd8d8827045926b2b16c18dc867fa8b2bdd",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(60, parsed.percentComplete)
        XCTAssertEqual(60, parsed.stateId)
        XCTAssertFalse(parsed.loadCartridgeState)
    }

    func testDetectingCartridgeStateStreamResponse_4() {
        let expected = DetectingCartridgeStateStreamResponse(cargo: Data([80, 0]))

        let parsed: DetectingCartridgeStateStreamResponse = MessageTester.test(
            "0089e3891a500078c840209382ea406c228d99294fb75a06b6034720bebf558af6",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(80, parsed.percentComplete)
        XCTAssertEqual(80, parsed.stateId)
        XCTAssertFalse(parsed.loadCartridgeState)
    }

    func testDetectingCartridgeStateStreamResponse_5() {
        let expected = DetectingCartridgeStateStreamResponse(cargo: Data([100, 0]))

        let parsed: DetectingCartridgeStateStreamResponse = MessageTester.test(
            "0089e3891a640078c840200446e27abb9bac31f8d1183f53dae99a2cc61d49b7ba",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(100, parsed.percentComplete)
        XCTAssertEqual(100, parsed.stateId)
        XCTAssertFalse(parsed.loadCartridgeState)
    }
}
