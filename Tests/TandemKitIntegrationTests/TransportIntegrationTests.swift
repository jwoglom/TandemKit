import CoreBluetooth
@testable import TandemKit
import XCTest

private final class CentralEvents: CBCentralManagerDelegate {
    var onDiscover: ((CBPeripheral) -> Void)?
    var onConnect: ((CBPeripheral) -> Void)?
    var onFailToConnect: ((Error?) -> Void)?

    func centralManagerDidUpdateState(_: CBCentralManager) {}

    func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData _: [String: Any], rssi _: NSNumber) {
        onDiscover?(peripheral)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral)
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        onFailToConnect?(error)
    }
}

private final class DiscoveryEvents: CBPeripheralDelegate {
    var onServices: (() -> Void)?
    var onCharacteristics: (() -> Void)?

    func peripheral(_: CBPeripheral, didDiscoverServices _: Error?) {
        onServices?()
    }

    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor _: CBService, error _: Error?) {
        onCharacteristics?()
    }
}

/// The virtual transport and `TandemPeripheralManager` against faketandem, without
/// `TandemBluetoothManager` or authentication: a failure here is in the link, not the driver.
final class TransportIntegrationTests: FaketandemIntegrationTestCase {
    func testApiVersionRoundTripsBelowTheDriver() throws {
        let events = CentralEvents()
        let central = CBCentralManager(
            delegate: events,
            queue: DispatchQueue(label: "TransportIntegrationTests"),
            endpoint: harness.endpoint,
            scanInterval: 0.5
        )
        defer {
            for peripheral in central.retrieveConnectedPeripherals(withServices: []) {
                central.cancelPeripheralConnection(peripheral)
            }
        }

        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var scanned: CBPeripheral?
        events.onDiscover = { peripheral in
            scanned = peripheral
            discovered.fulfill()
        }
        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
        wait(for: [discovered], timeout: 5)
        central.stopScan()
        let peripheral = try XCTUnwrap(scanned)

        let connected = expectation(description: "didConnect")
        events.onConnect = { _ in connected.fulfill() }
        events.onFailToConnect = { XCTFail("connect failed: \(String(describing: $0))") }
        central.connect(peripheral)
        wait(for: [connected], timeout: 5)

        let discovery = DiscoveryEvents()
        peripheral.delegate = discovery
        let servicesFound = expectation(description: "didDiscoverServices")
        discovery.onServices = { servicesFound.fulfill() }
        peripheral.discoverServices(ServiceUUID.all)
        wait(for: [servicesFound], timeout: 5)
        let characteristicsFound = expectation(description: "didDiscoverCharacteristicsFor")
        characteristicsFound.expectedFulfillmentCount = try XCTUnwrap(peripheral.services).count
        discovery.onCharacteristics = { characteristicsFound.fulfill() }
        for service in try XCTUnwrap(peripheral.services) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        wait(for: [characteristicsFound], timeout: 5)
        peripheral.delegate = nil

        let pumpManager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]))
        let peripheralManager = TandemPeripheralManager(TandemBluetoothManager(), peripheral, pumpManager) { _ in }
        let answered = expectation(description: "ApiVersionResponse")
        var received: ApiVersionResponse?
        DispatchQueue.global().async {
            peripheralManager.startNotify(
                service: ServiceUUID.PUMP_SERVICE,
                characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
            )
            received = peripheralManager.write(ApiVersionRequest())
            answered.fulfill()
        }
        wait(for: [answered], timeout: FaketandemHarness.responseTimeout + 5)

        XCTAssertGreaterThan(try XCTUnwrap(received, "no ApiVersionResponse").majorVersion, 0)
    }
}
