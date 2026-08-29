import CoreBluetooth

/// The pump's BLE surface as the rest of the driver sees it.
///
/// `TandemBluetoothManager` is the production implementation and owns the real `CBCentralManager`.
/// Everything above it — `TandemPumpManager`, its state-sync/basal extensions, `HistoryLogFetcher`
/// and the UI view models — talks to the pump only through this protocol, so the command sequences
/// they build can be exercised in tests against a stub instead of real hardware.
protocol PumpBluetoothConnection: AnyObject {
    /// Back-reference used to publish state changes and to look up the paired peripheral's UUID
    /// when reconnecting. Set by `TandemPumpManager` at init.
    var pumpManager: TandemPumpManager? { get set }

    /// The underlying central, when there is one. Only the real BLE path needs this (to request a
    /// low connection latency during pairing); a stub returns nil.
    var manager: CBCentralManager? { get }

    /// Starts scanning for Tandem pumps, calling `completion` once per advertisement. Returns false
    /// when Bluetooth is not powered on, in which case `completion` is never called.
    func startScan(_ completion: @escaping (_ result: TandemPumpScan) -> Void) -> Bool

    func stopScan()

    /// Connects to a specific peripheral, e.g. the one the user picked during pairing.
    func connect(_ peripheral: CBPeripheral, completion: @escaping (Error?) -> Void)

    /// Runs `completion` as a serialized command job: the pump is connected first if necessary, and
    /// `completion` then runs on the command queue so its (blocking) writes are serialized against
    /// every other command. `completion` runs exactly once, with a non-nil error if the connection
    /// could not be established.
    func ensureConnected(completion: @escaping (Error?) -> Void)

    /// Sends `request` and blocks until its response arrives, or nil on failure. Must be called
    /// from inside an `ensureConnected` job.
    func write<R: PumpRequest>(_ request: R, maxChunkSize: Int?) -> R.Response?

    /// Escape hatch for callers that only know their message at runtime — the debug tools, which
    /// pick one by name out of `MessageRegistry`. Everything else uses `write`.
    func writeUntyped(_ message: any Message, expecting: any Message.Type, maxChunkSize: Int?) -> (any Message)?

    func disconnect()

    /// Permanent teardown for a deleted pump: disconnect and suppress every automatic reconnect so
    /// the session cannot re-establish itself (and re-persist the pump's state) after removal.
    func deactivate()
}

extension PumpBluetoothConnection {
    /// Convenience for the common case; protocol requirements cannot carry default arguments.
    func write<R: PumpRequest>(_ request: R) -> R.Response? {
        write(request, maxChunkSize: nil)
    }

    func writeUntyped(_ message: any Message, expecting: any Message.Type) -> (any Message)? {
        writeUntyped(message, expecting: expecting, maxChunkSize: nil)
    }
}
