import CoreBluetooth
@testable import TandemKit
import XCTest

final class BTResponseParserTests: XCTestCase {
    private func message(_ opCode: UInt8, cargo: Data) -> AssembledMessage {
        AssembledMessage(opCode: opCode, txId: 1, payloadLength: max(0, cargo.count - 2), cargo: cargo)
    }

    func testAResponseDecodesFromItsOpcodeAndCharacteristic() {
        let decoded = BTResponseParser.decode(
            message(ApiVersionResponse.props.opCode, cargo: Data([3, 0, 7, 0, 0xAB, 0xCD])),
            characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        )

        XCTAssertEqual((decoded as? ApiVersionResponse)?.majorVersion, 3)
        XCTAssertEqual((decoded as? ApiVersionResponse)?.minorVersion, 7)
    }

    func testACargoShorterThanItsTypeIsDropped() {
        let decoded = BTResponseParser.decode(
            message(ApiVersionResponse.props.opCode, cargo: Data([3, 0, 7])),
            characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        )

        XCTAssertNil(decoded)
    }

    func testAnOpcodeWithNoResponseOnTheCharacteristicIsDropped() {
        let decoded = BTResponseParser.decode(
            message(ApiVersionResponse.props.opCode, cargo: Data([3, 0, 7, 0, 0xAB, 0xCD])),
            characteristic: CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS
        )

        XCTAssertNil(decoded)
    }
}
