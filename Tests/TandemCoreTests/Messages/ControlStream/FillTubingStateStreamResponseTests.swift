@testable import TandemKit
import XCTest

final class FillTubingStateStreamResponseTests: XCTestCase {
    func testFillTubingRequest_1() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761901dc9bee1fc0a8edcd9cbee43c109b046853fab2051262f1b84ca9",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_2() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761900e29bee1f69b046e6713fd3947e435f7a10381e7864ac91091a79",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_3() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761901e29bee1fe0744f64ededbc751612b0e00f367de5eaeccf5bfc96",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_4() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761900e39bee1f9d9e1e59f25f697025e559a930e69f91498ace97b83f",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_5() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761901e69bee1ffab75ebc85b1a37c7309d479a4038afb7e4d6fdb91c7",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_6() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761900ed9bee1f2a9429c51924b746e4a16d31d2981ce4e00e06b75eff",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_7() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761901f49bee1ff790d0d466213d4b56db4072b38c576a9a575be6b650",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_8() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0076e5761900f59bee1f9f053315303c66641ccc9e34555b50e153b58f8bc523",
            118,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_B_9() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0089e5891900249cee1f9b9e05be753ab197b4036913314c1266af76a668266a",
            -119,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_C_10() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0092e5921901379cee1fc0b37184a090390ff6bd41b1ac5566a0d66a53d6f74e",
            -110,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_C_11() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "0092e5921900449cee1f7714edde7740ac55f395f7c3030daf9da601fb86d7ae",
            -110,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_D_12() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "009de59d1900639cee1f835f372ea7bf7587005915997b64cc35afd9f06d9b1b",
            -99,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }

    func testFillTubingRequest_E_13() {
        let expected = FillTubingStateStreamResponse(cargo: Data([1]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "00a5e5a51901689cee1f3def52456aa152c855a664ea2f1d7846de2699807f3b",
            -91,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.buttonState)
        XCTAssertTrue(parsed.buttonDown)
    }

    func testFillTubingRequest_E_14() {
        let expected = FillTubingStateStreamResponse(cargo: Data([0]))

        let parsed: FillTubingStateStreamResponse = MessageTester.test(
            "00a5e5a51900769cee1fe8533421e37d68f6ee8b2b226361aa9282fe729065a5",
            -91,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.buttonState)
        XCTAssertFalse(parsed.buttonDown)
    }
}
