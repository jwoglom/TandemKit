import XCTest
@testable import TandemKit

final class ApiVersionRequestTests: XCTestCase {
    func testOpcode() {
        XCTAssertEqual(ApiVersionRequest.opCode, 0x20)
    }

    func testDefaultPayloadEmpty() {
        XCTAssertTrue(ApiVersionRequest().payload.isEmpty)
    }
}
