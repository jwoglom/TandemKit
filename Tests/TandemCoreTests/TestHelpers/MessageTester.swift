import CoreBluetooth
@testable import TandemKit
import XCTest

enum MessageTester {
    static func initPumpState(_: String, _: UInt32) {
        // Pump state not currently modeled; included for API parity with PumpX2 tests
    }

    static func test<T: Message>(
        _ rawHex: String,
        _ txId: Int,
        _ expectedPackets: Int,
        _ characteristic: CBUUID,
        _ expected: T,
        _ extraHexPackets: String...,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T {
        let props = T.props
        let tx = UInt8(truncatingIfNeeded: txId)
        XCTAssertEqual(characteristic, props.characteristic, "characteristic", file: file, line: line)

        let packets = ([rawHex] + extraHexPackets).map { Data(hexadecimalString: $0)! }
        var message = Data()
        for (index, packet) in packets.enumerated() {
            guard packet.count > 2 else {
                XCTFail("packet \(index) is \(packet.count) bytes", file: file, line: line)
                return expected
            }
            XCTAssertEqual(Int(packet[0]), packets.count - 1 - index, "packets remaining in packet \(index)", file: file, line: line)
            XCTAssertEqual(packet[1], tx, "txId in packet \(index)", file: file, line: line)
            message.append(packet.dropFirst(2))
        }

        guard message.count >= 5 else {
            XCTFail("message is \(message.count) bytes", file: file, line: line)
            return expected
        }
        let declaredLength = Int(message[2])
        let signatureLength = props.signed ? 24 : 0
        XCTAssertEqual(message[0], props.opCode, "opcode", file: file, line: line)
        XCTAssertEqual(message[1], tx, "txId", file: file, line: line)
        XCTAssertEqual(declaredLength, expected.cargo.count + signatureLength, "declared length", file: file, line: line)
        guard message.count == 3 + declaredLength + 2, declaredLength >= signatureLength else {
            XCTFail("message is \(message.count) bytes, declared length \(declaredLength)", file: file, line: line)
            return expected
        }
        assertHexEquals(
            CalculateCRC16(message.prefix(3 + declaredLength)),
            message.suffix(2),
            "CRC",
            file: file,
            line: line
        )

        // A signed message's packets carry an HMAC over a key the test doesn't have, so only an
        // unsigned one can be rebuilt byte for byte, as pumpX2 does.
        if !props.signed {
            let built = Packetize.parse(message: expected, authenticationKey: nil, txId: tx, timeSinceReset: nil)
            XCTAssertEqual(built.count, expectedPackets, "packets Packetize builds", file: file, line: line)
            // pumpX2's vectors give a multi-packet message either packet by packet or merged into one.
            let comparable = packets.count == 1 && built.count > 1
                ? [built.dropFirst().reduce(built[0]) { $0.merge(newPacket: $1) }]
                : built
            XCTAssertEqual(
                comparable.map { $0.build().hexadecimalString },
                packets.map(\.hexadecimalString),
                "packets Packetize builds",
                file: file,
                line: line
            )
        }

        let cargo = Data(message[3 ..< 3 + declaredLength - signatureLength])
        let parsed = T(cargo: cargo)
        assertHexEquals(expected.cargo, parsed.cargo, "cargo", file: file, line: line)
        return parsed
    }

    static func assertHexEquals(
        _ a: Data,
        _ b: Data,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(a.hexadecimalString, b.hexadecimalString, message, file: file, line: line)
    }
}
