@testable import TandemCore
import CoreBluetooth
import XCTest

// The characteristic constants live on `CharacteristicUUID` but are typed as
// `CBUUID`. Re-expose the ones used by the message fixtures as `CBUUID` static
// members so the `.CONSTANT` shorthand at the call sites resolves against the
// `CBUUID` parameter below.
extension CBUUID {
    static var CURRENT_STATUS_CHARACTERISTICS: CBUUID { CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS }
    static var AUTHORIZATION_CHARACTERISTICS: CBUUID { CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS }
    static var CONTROL_CHARACTERISTICS: CBUUID { CharacteristicUUID.CONTROL_CHARACTERISTICS }
}

enum MessageTester {
    static func initPumpState(_: String, _: UInt32) {
        // Pump state not currently modeled; included for API parity with PumpX2 tests
    }

    static func test<T: Message>(
        _ rawHex: String,
        _: Int,
        _: Int,
        _: CBUUID,
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
