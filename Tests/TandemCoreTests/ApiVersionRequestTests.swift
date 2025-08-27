import XCTest
@testable import TandemCore

final class ApiVersionRequestTests: XCTestCase {
    func testOpcode() {
        XCTAssertEqual(ApiVersionRequest.opCode, 0x20)
    }

    func testDefaultPayloadEmpty() {
        XCTAssertTrue(ApiVersionRequest().payload.isEmpty)
    }
}
