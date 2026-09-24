import CoreBluetooth
import Foundation
import LoopKit
@testable import TandemKit
import XCTest

#if !TANDEMKIT_VIRTUAL_PUMP
#error("TandemKitIntegrationTests needs the virtual pump build: scripts/integration-test.sh, or -xcconfig VirtualPump.xcconfig")
#endif

/// A running faketandem (`-transport virtual`) plus a real TandemKit driver stack on top of its
/// socket link. Nothing here is stubbed: TandemPumpManager -> TandemBluetoothManager ->
/// the virtual CBCentralManager -> TCP -> faketandem, with JPAKE and message signing running for real.
///
/// The emulator is reached through two environment variables. xcodebuild forwards variables named
/// `TEST_RUNNER_<NAME>` to the test process as `<NAME>`, so pass them as
/// `TEST_RUNNER_FAKETANDEM_GATT=127.0.0.1:8081 TEST_RUNNER_FAKETANDEM_API_URL=http://127.0.0.1:8080`
/// (`scripts/integration-test.sh` does this). Without them every test is skipped.
final class FaketandemHarness {
    /// `host:port` of the virtual GATT link (faketandem `-virtual-addr`).
    static let gattEnvironmentVariable = "FAKETANDEM_GATT"
    /// Base URL of the HTTP/websocket API (faketandem `-api-addr`).
    static let apiEnvironmentVariable = "FAKETANDEM_API_URL"

    /// Set on every reset, so a test never depends on the emulator's default.
    static let pairingCode = "123456"

    let endpoint: SocketPumpEndpoint
    let client: FaketandemClient
    let control: FaketandemControlSocket
    private let logger = TandemLogger(category: "FaketandemHarness")

    /// Request-log sequence at the last reset; `requestLogSinceReset()` starts here.
    private(set) var resetLogSequence = 0

    init(endpoint: SocketPumpEndpoint, apiBaseURL: URL) throws {
        self.endpoint = endpoint
        client = FaketandemClient(apiBaseURL: apiBaseURL)
        control = FaketandemControlSocket(apiBaseURL: apiBaseURL)
        try control.open()
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws
        -> FaketandemHarness
    {
        guard let gatt = environment[gattEnvironmentVariable], let api = environment[apiEnvironmentVariable] else {
            throw XCTSkip(
                "\(gattEnvironmentVariable) / \(apiEnvironmentVariable) not set; run via scripts/integration-test.sh"
            )
        }
        guard let endpoint = SocketPumpEndpoint(gatt) else {
            throw XCTSkip("\(gattEnvironmentVariable)=\(gatt) is not host:port")
        }
        guard let url = URL(string: api), url.scheme != nil, url.host != nil else {
            throw XCTSkip("\(apiEnvironmentVariable)=\(api) is not a URL")
        }
        return try FaketandemHarness(endpoint: endpoint, apiBaseURL: url)
    }

    func close() {
        control.close()
    }

    // MARK: - Emulator state

    /// Back to a pump that has never met this driver: nobody attached, no session key, no cached
    /// long-term key, the known pairing code, advertising PairStep2, on the real clock with no
    /// faults armed and an empty request log.
    func reset() throws {
        try client.clearFaults()
        if try client.snapshot().connection.connected {
            try control.disconnectPump()
            try IntegrationWait.until("emulator to drop the previous central", timeout: 10) {
                try !client.snapshot().connection.connected
            }
        }
        _ = try control.setPairingCode(Self.pairingCode)
        _ = try control.resetLongTermKey()
        try client.setClock(mode: "real", pumpOffsetSeconds: 0)
        try client.setPairingState(.pairStep2)
        try client.clearRequestLog()
        resetLogSequence = try client.snapshot().requestLog.lastSeq

        let auth = try client.snapshot().auth
        precondition(!auth.authenticated && !auth.longTermKeyPresent, "reset left auth state behind: \(auth)")
    }

    /// The pump's record of the exchange since the last reset (or since `since`).
    func requestLog(since: Int? = nil) throws -> [FaketandemLogEntry] {
        try client.requestLog(since: since ?? resetLogSequence).entries
    }

    /// Inbound messages the pump parsed, in order: (opcode, name, characteristic).
    func requestsSeen(since: Int? = nil) throws -> [(opcode: Int, message: String, characteristic: String)] {
        try requestLog(since: since).filter(\.isRequest).map {
            (opcode: $0.opcode ?? -1, message: $0.message ?? "", characteristic: $0.characteristic ?? "")
        }
    }

    /// Reads the `hello` frame directly, the way a scan probe does, without going through the driver.
    func readHello() throws -> VirtualPumpHello {
        let link = try SocketLink(connectTo: endpoint)
        defer { link.close() }
        guard let message = try link.readMessage(timeout: 5), let hello = VirtualPumpHello(message) else {
            throw FaketandemClientError.transport("virtual pump did not send hello")
        }
        return hello
    }

    // MARK: - Driver

    /// One real driver stack. Everything a test needs to reach is exposed; the delegate is attached
    /// in Trio's order (delegate first, then queue) unless `attachDelegate` is false.
    struct Driver {
        let central: CBCentralManager
        let bluetooth: TandemBluetoothManager
        let manager: TandemPumpManager
        let delegate: MockPumpManagerDelegate
        let delegateQueue: DispatchQueue
        let clock: TandemClock

        /// Drains the delegate queue so assertions see every callback issued so far.
        func drainDelegate() {
            delegateQueue.sync {}
        }

        var bolusEvents: [NewPumpEvent] {
            drainDelegate()
            return delegate.pumpEvents.filter { $0.dose?.type == .bolus }
        }
    }

    /// `clock` defaults to a ManualClock starting now, so a test can jump the driver's idea of time
    /// (bolus estimated end, sync throttles) without waiting; the emulator stays on its own clock.
    func makeDriver(
        state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:]),
        clock: TandemClock = ManualClock(Date()),
        attachDelegate: Bool = true
    ) -> Driver {
        VirtualPump.endpoint = endpoint
        VirtualPump.scanInterval = 0.5
        let bluetooth = TandemBluetoothManager()
        let central = bluetooth.manager!
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "com.jwoglom.TandemKitIntegrationTests.delegate")
        if attachDelegate {
            manager.pumpManagerDelegate = delegate
            manager.delegateQueue = queue
        }
        return Driver(
            central: central,
            bluetooth: bluetooth,
            manager: manager,
            delegate: delegate,
            delegateQueue: queue,
            clock: clock
        )
    }

    /// Stops the driver's auto-reconnect, drops the link and waits for the pump to see it go, so the
    /// next test's driver is not refused as `busy`.
    func shutDown(_ driver: Driver, timeout: TimeInterval = 40) throws {
        let done = ResultBox<Bool>()
        // prepareForDeactivation writes DisconnectPumpRequest synchronously on the caller's thread.
        DispatchQueue.global().async {
            driver.manager.prepareForDeactivation { _ in done.set(true) }
        }
        _ = try done.wait("driver deactivation", timeout: timeout)
        try IntegrationWait.until("emulator to see the driver disconnect", timeout: 10) {
            try !client.snapshot().connection.connected
        }
    }

    // MARK: - Flows (the same entry points TandemKitUI's onboarding uses)

    /// Scans until an advertisement satisfying `accept` arrives, then stops scanning.
    func discover(
        _ driver: Driver,
        timeout: TimeInterval = 15,
        accept: @escaping (TandemPumpScan) -> Bool = { _ in true }
    ) throws -> TandemPumpScan {
        let box = ResultBox<TandemPumpScan>()
        guard driver.bluetooth.startScan({ scan in
            if !box.isSet, accept(scan) {
                box.set(scan)
            }
        }) else {
            throw FaketandemClientError.transport("startScan refused; central state \(driver.central.state.rawValue)")
        }
        defer { driver.bluetooth.stopScan() }
        return try box.wait("virtual pump advertisement", timeout: timeout)
    }

    /// `TandemPumpManager.pairPump`, as TandemKitScanViewModel calls it. Returns the completion's
    /// error; JPAKE through pumpX2's jpake-server takes a few seconds.
    func pair(
        _ driver: Driver,
        with scan: TandemPumpScan,
        code: String = FaketandemHarness.pairingCode,
        timeout: TimeInterval = 90
    ) throws -> Error? {
        let box = ResultBox<Error?>()
        driver.manager.pairPump(code: code, peripheral: scan.peripheral) { box.set($0) }
        return try box.wait("pairPump completion", timeout: timeout)
    }

    /// Discover + pair with the known code; throws if pairing fails.
    @discardableResult
    func pair(_ driver: Driver, timeout: TimeInterval = 90) throws -> TandemPumpScan {
        let scan = try discover(driver)
        if let error = try pair(driver, with: scan, timeout: timeout) {
            throw error
        }
        return scan
    }

    /// A full `syncPumpData`, returning its lastSync.
    func sync(_ driver: Driver, timeout: TimeInterval = 180) throws -> Date? {
        let box = ResultBox<Date?>()
        driver.manager.syncPumpData { box.set($0) }
        let lastSync = try box.wait("syncPumpData completion", timeout: timeout)
        driver.drainDelegate()
        return lastSync
    }
}
