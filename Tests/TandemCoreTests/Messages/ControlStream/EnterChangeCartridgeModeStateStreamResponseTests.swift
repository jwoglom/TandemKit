@testable import TandemKit
import XCTest

final class EnterChangeCartridgeModeStateStreamResponseTests: XCTestCase {
    func testChangeCartridgeStateStreamResponse_ReadyToRemoveCart() {
        let expected = EnterChangeCartridgeModeStateStreamResponse(stateId: 2)

        let parsed: EnterChangeCartridgeModeStateStreamResponse = MessageTester.test(
            "0083e18319026dc840203e1a10e4806b4079adf00d1cfe2894949c7d58333915",
            -125,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.stateId)
        XCTAssertEqual(.readyToChange, parsed.state)
    }
}
