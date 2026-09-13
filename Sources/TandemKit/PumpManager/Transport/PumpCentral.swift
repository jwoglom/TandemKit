import CoreBluetooth
import Foundation

/// The central's side of the link. Implementations hand back the same `PumpPeripheral` object for
/// a given identifier from every call (`didDiscover`, `didConnect`, `retrieve*`), because the
/// driver caches the reference across connects and reconnects through it.
///
/// Every delegate callback — central and peripheral — is delivered asynchronously on one serial
/// queue owned by the central, matching CoreBluetooth's contract. `centralDidUpdateState` is first
/// delivered after `delegate` has been set, never from the initializer.
protocol PumpCentral: AnyObject {
    var state: CBManagerState { get }
    var isScanning: Bool { get }
    var delegate: PumpCentralDelegate? { get set }

    func scanForPeripherals(withServices services: [CBUUID], allowDuplicates: Bool)
    func stopScan()

    func connect(_ peripheral: PumpPeripheral)
    func cancelPeripheralConnection(_ peripheral: PumpPeripheral)

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [PumpPeripheral]
    func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [PumpPeripheral]
}

protocol PumpCentralDelegate: AnyObject {
    func centralDidUpdateState(_ central: PumpCentral)
    func central(
        _ central: PumpCentral,
        didDiscover peripheral: PumpPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    )
    func central(_ central: PumpCentral, didConnect peripheral: PumpPeripheral)
    func central(_ central: PumpCentral, didDisconnect peripheral: PumpPeripheral, error: Error?)
    func central(_ central: PumpCentral, didFailToConnect peripheral: PumpPeripheral, error: Error?)
}

/// Optional capability: asking the OS for a shorter connection interval. Only CoreBluetooth has
/// anything to do here; a transport without it simply does not conform.
protocol PumpCentralLatencyControl: AnyObject {
    func requestLowLatency(for peripheral: PumpPeripheral)
}
