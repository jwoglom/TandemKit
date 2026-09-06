@testable import TandemKit
import XCTest

/// Opcode -23 on the control stream carries two messages that differ only by payload size:
/// ExitFillTubingModeStateStreamResponse (1 byte) and PumpingStateStreamResponse (5 bytes).
///
/// Both are signed, so the wire cargo carries a 24-byte trailer, and `BTResponseParser` hands the
/// message everything after the 5-byte packet header — which also leaves the packet's 2-byte CRC
/// on the end. The payloads here are synthetic, shaped like the packets a pump sends.
final class ControlStreamOpcode23Tests: XCTestCase {
    private static let signedTrailer = Data(repeating: 0xAB, count: 24)
    private static let crc = Data([0x12, 0x34])

    /// Cargo as `didUpdateValueFor` hands it over: payload + signed trailer + packet CRC.
    private func wireCargo(payload: Data) -> Data {
        payload + Self.signedTrailer + Self.crc
    }

    /// A full packet: [packetsRemaining][txId][opCode][txId][payloadLength] + cargo.
    private func packet(payload: Data) -> Data {
        Data([0x00, 0x94, ExitFillTubingModeStateStreamResponse.props.opCode, 0x94, UInt8(payload.count + 24)])
            + wireCargo(payload: payload)
    }

    func testExitFillTubingStatePayloadIgnoresTheSignedTrailer() {
        let response = ExitFillTubingModeStateStreamResponse(cargo: wireCargo(payload: Data([0x01])))

        XCTAssertEqual(response.stateId, 1)
        XCTAssertEqual(response.state, .tubingFilled)
        // The trailer must not be mistaken for a pumping-state payload.
        XCTAssertFalse(response.isPumpingStateSetAfterStartUp)
        XCTAssertEqual(response.stateBitmask, 0)
        XCTAssertEqual(response.cargo, Data([0x01]))
    }

    func testExitFillTubingStateNotComplete() {
        let response = ExitFillTubingModeStateStreamResponse(cargo: wireCargo(payload: Data([0x00])))

        XCTAssertEqual(response.state, .notComplete)
        XCTAssertEqual(response.stateBitmask, 0)
    }

    func testPumpingStatePayloadIsReadPastTheSignedTrailer() {
        // isDeliveringTherapy | deliveringBasal == 33, little-endian.
        let payload = Data([0x01, 0x21, 0x00, 0x00, 0x00])
        let response = PumpingStateStreamResponse(cargo: wireCargo(payload: payload))

        XCTAssertTrue(response.isPumpingStateSetAfterStartUp)
        XCTAssertEqual(response.stateBitmask, 33)
        XCTAssertEqual(response.states, [.isDeliveringTherapy, .deliveringBasal])
        XCTAssertEqual(response.cargo, payload)
    }

    /// pumpX2's cargo stops at the signed trailer; TandemKit's keeps the CRC. Both must parse.
    func testCargoWithoutTheTrailingCrcAlsoParses() {
        let exit = ExitFillTubingModeStateStreamResponse(cargo: Data([0x01]) + Self.signedTrailer)
        XCTAssertEqual(exit.state, .tubingFilled)
        XCTAssertEqual(exit.stateBitmask, 0)

        let pumping = PumpingStateStreamResponse(
            cargo: Data([0x00, 0x02, 0x00, 0x00, 0x00]) + Self.signedTrailer
        )
        XCTAssertFalse(pumping.isPumpingStateSetAfterStartUp)
        XCTAssertEqual(pumping.stateBitmask, 2)
    }

    func testLocallyBuiltCargoIsLeftAlone() {
        XCTAssertEqual(ExitFillTubingModeStateStreamResponse(stateId: 1).state, .tubingFilled)

        let pumping = PumpingStateStreamResponse(isPumpingStateSetAfterStartUp: true, stateBitmask: 16)
        XCTAssertEqual(pumping.stateBitmask, 16)
        XCTAssertTrue(pumping.isPumpingStateSetAfterStartUp)
    }

    func testRequestIsChosenByThePacketsPayloadLength() {
        XCTAssertTrue(
            ControlStreamMessages.determineRequestMessage(rawBtValue: packet(payload: Data([0x01])))
                is NonexistentExitFillTubingModeStateStreamRequest
        )
        XCTAssertTrue(
            ControlStreamMessages
                .determineRequestMessage(rawBtValue: packet(payload: Data([0x01, 0x21, 0x00, 0x00, 0x00])))
                is NonexistentPumpingStateStreamRequest
        )
    }
}
