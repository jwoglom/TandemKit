@testable import TandemKit
import XCTest

final class SetSensorTypeResponseTests: XCTestCase {
    func testBuildCargo_ackSuccess() {
        MessageTester.assertHexEquals(Data([0x00, 0x00]), SetSensorTypeResponse(status: 0, statusAcknowledgement: 0).cargo)
    }

    func testConstructAndGetters_ackSuccess() {
        let resp = SetSensorTypeResponse(status: 0, statusAcknowledgement: 0)

        XCTAssertEqual(0, resp.status)
        XCTAssertEqual(0, resp.statusAcknowledgement)
        XCTAssertEqual(.success, resp.statusAcknowledgementType)
    }

    func testParse_nackInvalidCgmType() {
        let resp = SetSensorTypeResponse(cargo: Data([0x01, 0x02]))

        XCTAssertEqual(1, resp.status)
        XCTAssertEqual(2, resp.statusAcknowledgement)
        XCTAssertEqual(.invalidCgmType, resp.statusAcknowledgementType)
    }

    func testParse_nackMissingPackage() {
        let resp = SetSensorTypeResponse(cargo: Data([0x01, 0x04]))

        XCTAssertEqual(1, resp.status)
        XCTAssertEqual(.missingOrInvalidCgmSupportPackage, resp.statusAcknowledgementType)
    }
}
