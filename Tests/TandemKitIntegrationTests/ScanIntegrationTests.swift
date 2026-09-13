import CoreBluetooth
@testable import TandemKit
import XCTest

final class ScanIntegrationTests: FaketandemIntegrationTestCase {
    private func manufacturerData(_ scan: TandemPumpScan) -> Data? {
        scan.advertisementData?[CBAdvertisementDataManufacturerDataKey] as? Data
    }

    func testScanDiscoversTheVirtualPump() throws {
        let hello = try harness.readHello()
        let driver = makeDriver()

        let scan = try harness.discover(driver)

        XCTAssertEqual(scan.bleIdentifier, hello.peripheralId.uuidString)
        XCTAssertEqual(scan.name, hello.name)
        XCTAssertEqual(scan.peripheral.identifier, hello.peripheralId)
        XCTAssertEqual(manufacturerData(scan), hello.manufacturerData)
        XCTAssertEqual(
            manufacturerData(scan)?.last,
            FaketandemPairingState.pairStep2.manufacturerByte,
            "reset leaves the pump in PairStep2, which advertises 0x12"
        )
        XCTAssertEqual(hello.pairingState, FaketandemPairingState.pairStep2.rawValue)
        XCTAssertFalse(scan.peripheral.isConnected, "a scan must not attach")
        XCTAssertFalse(try harness.client.snapshot().connection.connected)
    }

    func testAdvertisementTracksThePairingState() throws {
        let driver = makeDriver()
        _ = try harness.discover(driver)

        try harness.client.setPairingState(.pairStep1)
        let step1 = try harness.discover(driver) { [self] in
            manufacturerData($0)?.last == FaketandemPairingState.pairStep1.manufacturerByte
        }
        XCTAssertEqual(manufacturerData(step1)?.last, 0x11)

        try harness.client.setPairingState(.discoverableOnly)
        let discoverable = try harness.discover(driver) { [self] in
            manufacturerData($0)?.last == FaketandemPairingState.discoverableOnly.manufacturerByte
        }
        XCTAssertEqual(manufacturerData(discoverable)?.last, 0x10)
    }

    func testANotDiscoverablePumpIsNotAdvertised() throws {
        let driver = makeDriver()
        try harness.client.setPairingState(.notDiscoverable)

        XCTAssertThrowsError(try harness.discover(driver, timeout: 2)) { error in
            XCTAssertTrue(error is IntegrationWaitTimeout, "got \(error)")
        }
    }
}
