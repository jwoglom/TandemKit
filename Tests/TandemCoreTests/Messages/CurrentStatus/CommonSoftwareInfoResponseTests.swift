@testable import TandemKit
import XCTest

final class CommonSoftwareInfoResponseTests: XCTestCase {
    // Maintainer's Tandem Mobi on Control-IQ 7.7.0.1, reply to an ARM request.
    func testCommonSoftwareInfoResponseMobi7701Arm() {
        let raw = Data(hexadecimalString: "006663383265343935646465383266636600167a0f00000000006663383265343935646465383266636600167a0f0000000000")!
        let parsed = CommonSoftwareInfoResponse(cargo: raw)

        XCTAssertEqual(parsed.mcuTypeId, 0)
        XCTAssertEqual(parsed.mcuType, .arm)
        XCTAssertEqual(parsed.appSoftwareVersion, "fc82e495dde82fcf")
        XCTAssertEqual(parsed.appSoftwarePartNumber, 1_014_294)
        XCTAssertEqual(parsed.appSoftwarePartRevisionNumber, 0)
        XCTAssertEqual(parsed.appSoftwarePartDashNumber, 0)
        XCTAssertEqual(parsed.bootloaderVersion, "fc82e495dde82fcf")
        XCTAssertEqual(parsed.bootloaderPartNumber, 1_014_294)
        XCTAssertEqual(parsed.bootloaderPartRevisionNumber, 0)
        XCTAssertNil(parsed.bootloaderPartDashNumber)
    }

    // Maintainer's Tandem Mobi on Control-IQ+ 7.9.0.2, reply to a BLE request.
    func testCommonSoftwareInfoResponseMobi7902Ble() {
        let raw = Data(hexadecimalString: "016433633931616435346331326232323800b3870f00000000006433633931616435346331326232323800b3870f0000000000")!
        let parsed = CommonSoftwareInfoResponse(cargo: raw)

        XCTAssertEqual(parsed.mcuType, .ble)
        XCTAssertEqual(parsed.appSoftwareVersion, "d3c91ad54c12b228")
        XCTAssertEqual(parsed.appSoftwarePartNumber, 1_017_779)
        XCTAssertEqual(parsed.bootloaderVersion, "d3c91ad54c12b228")
        XCTAssertEqual(parsed.bootloaderPartNumber, 1_017_779)
        XCTAssertEqual(parsed.bootloaderPartRevisionNumber, 0)

        let built = CommonSoftwareInfoResponse(
            mcuTypeId: 1,
            appSoftwareVersion: "d3c91ad54c12b228",
            appSoftwarePartNumber: 1_017_779,
            appSoftwarePartRevisionNumber: 0,
            bootloaderVersion: "d3c91ad54c12b228",
            bootloaderPartNumber: 1_017_779,
            bootloaderPartRevisionNumber: 0
        )
        MessageTester.assertHexEquals(raw, built.cargo)
    }

    // Maintainer's Tandem Mobi on Control-IQ+ 7.9.0.1, reply to an ARM request.
    func testCommonSoftwareInfoResponseMobi7901Arm() {
        let raw = Data(hexadecimalString: "0034323064643130663137343365623765000b830f000000000034323064643130663137343365623765000b830f0000000000")!
        let parsed = CommonSoftwareInfoResponse(cargo: raw)

        XCTAssertEqual(parsed.mcuType, .arm)
        XCTAssertEqual(parsed.appSoftwareVersion, "420dd10f1743eb7e")
        XCTAssertEqual(parsed.appSoftwarePartNumber, 1_016_587)
        XCTAssertEqual(parsed.bootloaderVersion, "420dd10f1743eb7e")
        XCTAssertEqual(parsed.bootloaderPartNumber, 1_016_587)
    }

    // No t:slim X2 response has been captured; this checks the layout the X2 app reads.
    func testCommonSoftwareInfoResponseX2LayoutRoundTrip() {
        let built = CommonSoftwareInfoResponse(
            appSoftwareVersion: "0123456789abcdef",
            appSoftwarePartNumber: 1_000_001,
            appSoftwarePartDashNumber: 2,
            appSoftwarePartRevisionNumber: 3,
            bootloaderVersion: "fedcba9876543210",
            bootloaderPartNumber: 1_000_004,
            bootloaderPartDashNumber: 5,
            bootloaderPartRevisionNumber: 6
        )
        let parsed = CommonSoftwareInfoResponse(cargo: built.cargo)

        XCTAssertNil(parsed.mcuTypeId)
        XCTAssertEqual(parsed.appSoftwareVersion, "0123456789abcdef")
        XCTAssertEqual(parsed.appSoftwarePartNumber, 1_000_001)
        XCTAssertEqual(parsed.appSoftwarePartDashNumber, 2)
        XCTAssertEqual(parsed.appSoftwarePartRevisionNumber, 3)
        XCTAssertEqual(parsed.bootloaderVersion, "fedcba9876543210")
        XCTAssertEqual(parsed.bootloaderPartNumber, 1_000_004)
        XCTAssertEqual(parsed.bootloaderPartDashNumber, 5)
        XCTAssertEqual(parsed.bootloaderPartRevisionNumber, 6)
    }

    func testCommonSoftwareInfoRequestMcuType() {
        XCTAssertEqual(CommonSoftwareInfoRequest(mcuType: .ble).cargo, Data([1]))
        XCTAssertEqual(CommonSoftwareInfoRequest(mcuType: .ble).mcuType, .ble)
        XCTAssertNil(CommonSoftwareInfoRequest().mcuType)
    }
}
