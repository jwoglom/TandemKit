import XCTest
@testable import TandemCore

enum MessageTester {
    static func initPumpState(_ pumpAuthenticationKey: String, _ timeSinceReset: UInt32) {
        // Stub for PumpX2's initPumpState; no-op in TandemKit tests
    }

    static func test<T: Message>(
        _ rawHex: String,
        _ txId: Int,
        _ expectedPackets: Int,
        _ characteristic: CharacteristicUUID,
        _ expected: T,
        _ extraHexPackets: String...
    ) -> T {
        var packets = [rawHex] + extraHexPackets
        var combined = Data()
        for (idx, hex) in packets.enumerated() {
            var data = Data(hexadecimalString: hex)!
            if idx > 0 { data = data.dropFirst(2) }
            combined.append(data)
        }
        return T.init(cargo: combined.suffix(expected.cargo.count))
    }

    static func assertHexEquals(_ a: Data, _ b: Data, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.hexadecimalString, b.hexadecimalString, file: file, line: line)
    }
}
