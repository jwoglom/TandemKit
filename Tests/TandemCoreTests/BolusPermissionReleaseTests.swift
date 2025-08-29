import XCTest
@testable import TandemCore

final class BolusPermissionReleaseTests: XCTestCase {
    func testRequestEncodingDecoding() {
        let bolusId: UInt32 = 10676
        let expectedCargo = Data([0xB4, 0x29, 0x00, 0x00])

        // Encoding
        let req = BolusPermissionReleaseRequest(bolusId: bolusId)
        XCTAssertEqual(req.cargo, expectedCargo)

        // Decoding
        let decoded = BolusPermissionReleaseRequest(cargo: expectedCargo)
        XCTAssertEqual(decoded.bolusId, bolusId)
    }

    func testResponseEncodingDecoding() {
        let status = 0
        let expectedCargo = Data([0x00])

        // Encoding
        let res = BolusPermissionReleaseResponse(status: status)
        XCTAssertEqual(res.cargo, expectedCargo)

        // Decoding
        let decoded = BolusPermissionReleaseResponse(cargo: expectedCargo)
        XCTAssertEqual(decoded.status, status)
        XCTAssertEqual(decoded.releaseStatus, .success)
    }
}
