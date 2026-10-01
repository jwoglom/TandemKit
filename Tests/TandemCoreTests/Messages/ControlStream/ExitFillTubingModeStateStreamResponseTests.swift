@testable import TandemKit
import XCTest

final class ExitFillTubingModeStateStreamResponseTests: XCTestCase {
    func testExitFillTubingModeStateStreamResponse() {
        let expected = ExitFillTubingModeStateStreamResponse(stateId: 0)

        let parsed: ExitFillTubingModeStateStreamResponse = MessageTester.test(
            "0091e9911900aec84020f5be25220634beb8ffff2cad2cf936582ee0226d2f28",
            -111,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.stateId)
        XCTAssertEqual(.notComplete, parsed.state)
        XCTAssertFalse(parsed.isPumpingStateSetAfterStartUp)
        XCTAssertEqual(0, parsed.stateBitmask)
    }
}
