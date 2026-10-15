@testable import TandemKit
import XCTest

final class ControlStreamMessagesTests: XCTestCase {
    private let sharedByCartridgeStreams = DetectingCartridgeStateStreamResponse.props.opCode
    private let sharedByFillAndPumpingStreams = PumpingStateStreamResponse.props.opCode

    func testDetectingAndLoadCartridgeAreToldApartByDeclaredLength() {
        for length in [2, 26] {
            XCTAssertTrue(
                ControlStreamMessages.responseType(opCode: sharedByCartridgeStreams, payloadLength: length)
                    == DetectingCartridgeStateStreamResponse.self,
                "length \(length)"
            )
        }
        for length in [1, 25] {
            XCTAssertTrue(
                ControlStreamMessages.responseType(opCode: sharedByCartridgeStreams, payloadLength: length)
                    == LoadCartridgeStateStreamResponse.self,
                "length \(length)"
            )
        }
    }

    func testPumpingAndExitFillTubingAreToldApartByDeclaredLength() {
        for length in [5, 29] {
            XCTAssertTrue(
                ControlStreamMessages.responseType(opCode: sharedByFillAndPumpingStreams, payloadLength: length)
                    == PumpingStateStreamResponse.self,
                "length \(length)"
            )
        }
        for length in [1, 25] {
            XCTAssertTrue(
                ControlStreamMessages.responseType(opCode: sharedByFillAndPumpingStreams, payloadLength: length)
                    == ExitFillTubingModeStateStreamResponse.self,
                "length \(length)"
            )
        }
    }

    func testAnOpcodeOffTheControlStreamHasNoType() {
        XCTAssertNil(ControlStreamMessages.responseType(opCode: ApiVersionResponse.props.opCode, payloadLength: 4))
    }

    /// A whole signed message is 33 bytes for detecting progress and 32 for a load state, so a
    /// split on packet length at 26 took both for detecting progress.
    func testALoadCartridgeStateWholeInOneNotificationIsALoadState() throws {
        let detecting = try XCTUnwrap(Data(hexadecimalString: "0089e3891a140078c84020f4eabab90ec17db0da1b4d99095f92c063a1b1b9456a"))
        let load = Data([0x00, 0x8A, sharedByCartridgeStreams, 0x8A, 25, 2]) + Data(repeating: 0xA5, count: 26)
        XCTAssertEqual(load.count, 32)

        XCTAssertTrue(ControlStreamMessages.determineRequestMessage(rawBtValue: detecting) is NonexistentDetectingCartridgeStateStreamRequest)
        XCTAssertTrue(ControlStreamMessages.determineRequestMessage(rawBtValue: load) is NonexistentLoadCartridgeStateStreamRequest)
    }
}
