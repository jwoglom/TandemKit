@testable import TandemKit
import XCTest

final class SetSensorTypeRequestTests: XCTestCase {
    func testBuildCargo_dexcomG7() {
        MessageTester.assertHexEquals(Data([0x03]), SetSensorTypeRequest(sensorTypeId: 3).cargo)
    }

    func testBuildCargo_notApplicable() {
        MessageTester.assertHexEquals(Data([0x00]), SetSensorTypeRequest(sensorTypeId: 0).cargo)
    }

    func testConstructAndParse_dexcomG6() {
        let req = SetSensorTypeRequest(sensorTypeId: 1)

        XCTAssertEqual(1, req.sensorTypeId)
        XCTAssertEqual(.dexcomG6, CGMStatusV2Response.CGMSensorType(rawValue: req.sensorTypeId))
    }

    func testConstructFromEnum() {
        let req = SetSensorTypeRequest(sensorType: .dexcomG7)

        XCTAssertEqual(3, req.sensorTypeId)
        XCTAssertEqual(.dexcomG7, CGMStatusV2Response.CGMSensorType(rawValue: req.sensorTypeId))
    }

    func testParse() {
        let req = SetSensorTypeRequest(cargo: Data([0x02]))

        XCTAssertEqual(2, req.sensorTypeId)
        XCTAssertEqual(.fsl2, CGMStatusV2Response.CGMSensorType(rawValue: req.sensorTypeId))
    }
}
