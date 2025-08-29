import XCTest
@testable import TandemCore

enum MessageTester {
    static func initPumpState(_ pumpAuthenticationKey: String, _ timeSinceReset: UInt32) {
        // Pump state not currently modeled; included for API parity with PumpX2 tests
    }

    static func test<T: Message>(
        _ rawHex: String,
        _ txId: Int,
        _ expectedPackets: Int,
        _ characteristic: CharacteristicUUID,
        _ expected: T,
        _ extraHexPackets: String...
    ) -> T {
        var payload = Data()
        let first = Data(hexadecimalString: rawHex)!
        payload.append(first.dropFirst(5))
        for hex in extraHexPackets {
            let data = Data(hexadecimalString: hex)!
            payload.append(data.dropFirst(2))
        }
        payload = payload.dropLast(2)
        let cargo = Data(payload.prefix(expected.cargo.count))
        return T.init(cargo: cargo)
    }

    static func assertHexEquals(_ a: Data, _ b: Data, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.hexadecimalString, b.hexadecimalString, file: file, line: line)
    }
}
