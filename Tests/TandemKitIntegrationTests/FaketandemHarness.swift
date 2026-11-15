import CoreBluetooth
import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
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
        control = try FaketandemControlSocket.shared(apiBaseURL: apiBaseURL)
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

    // MARK: - Emulator state

    /// Back to a pump that has never met this driver: nobody attached, no session key, no cached
    /// long-term key, the known pairing code, advertising PairStep2, on the real clock at the
    /// default ATT MTU with no faults armed and an empty request log.
    /// faketandem's defaults (`state.DefaultDeliveryLimits`), pumpX2's test-vector values.
    static let defaultMaxBolusMilliunits = 25000
    static let defaultMaxBasalMilliunits = 5000
    /// U/hr; `FaketandemIDPProfile.emulatorDefault`'s one segment.
    static let defaultBasalRate = 0.85
    /// `SetPumpSoundsRequest` writes the sounds into the pump globals the emulator launched with.
    private static var launchPumpGlobals: [String: Any]?
    /// D15 gives the pump another serial.
    private static var launchPumpVersion: [String: Any]?

    func reset() throws {
        try client.clearFaults()
        // First: a cycle left on writes BasalDelivery records once the clock runs in real time again.
        if try client.snapshot().basalCycle != nil {
            try client.setState(["basal_cycle_enabled": false, "controliq_algorithm_rate": -1, "cgm_available": true])
        }
        if try client.transport().mtuConfigurable {
            try client.setATTMTU(FaketandemClient.defaultATTMTU)
        }
        if try client.snapshot().connection.connected {
            try control.disconnectPump()
            try IntegrationWait.until("emulator to drop the previous central", timeout: 10) {
                try !client.snapshot().connection.connected
            }
        }
        _ = try control.setPairingCode(Self.pairingCode)
        _ = try control.resetLongTermKey()
        // Naming the zone sets the pump's clock back to the phone's local time, which a test that
        // changed the pump's clock or the phone's zone left elsewhere.
        try client.setClock(mode: "real", pumpOffsetSeconds: 0, pumpTimezone: TimeZone.current.identifier)
        // Before the erase, which takes the resume's records with it.
        if try client.snapshot().basal.suspended {
            try client.resume(clearAlarms: true)
        }
        // An earlier test's records, dated on its clock, reach a fresh driver with dose reporting
        // on as pump boluses it never heard of.
        try client.eraseHistory()
        try client.setPairingState(.pairStep2)
        // An emulator without profile or limit modelling has nothing to restore.
        let snapshot = try client.snapshot()
        if snapshot.idpProfiles != nil {
            try client.setIDPProfiles([.emulatorDefault])
        }
        // Tests stage the rate in force, and a profile write sets it too. An earlier test's bolus
        // is dated on that test's clock, which may be ahead of this one's, and would count in full.
        // A standing alarm would reach the next driver as an `.alarm` event.
        try client.setState(["closed_loop_enabled": false, "basal_rate": Self.defaultBasalRate, "iob": 0, "clear_alerts": true])
        if let globals = Self.launchPumpGlobals {
            try client.setSettingsConfig(globals, for: "PumpGlobalsRequest")
        } else {
            Self.launchPumpGlobals = try client.settingsConfig(for: "PumpGlobalsRequest")
        }
        if let version = Self.launchPumpVersion {
            try client.setSettingsConfig(version, for: "PumpVersionBRequest")
        } else {
            Self.launchPumpVersion = try client.settingsConfig(for: "PumpVersionBRequest")
        }
        if snapshot.limits != nil {
            try client.setState(["max_bolus_milliunits": Self.defaultMaxBolusMilliunits, "max_basal_milliunits": Self.defaultMaxBasalMilliunits])
        }
        try client.clearRequestLog()
        resetLogSequence = try client.snapshot().requestLog.lastSeq

        let auth = try client.snapshot().auth
        precondition(!auth.authenticated && !auth.longTermKeyPresent, "reset left auth state behind: \(auth)")
    }

    /// The pump's record of the exchange since the last reset (or since `since`).
    func requestLog(since: Int? = nil) throws -> [FaketandemLogEntry] {
        try client.requestLog(since: since ?? resetLogSequence).entries
    }

    /// Inbound messages the pump parsed, in order: (opcode, name, characteristic). The log carries
    /// opcodes as signed bytes (Control opcodes are >= 0x80); they are normalised to 0...255 here.
    func requestsSeen(since: Int? = nil) throws -> [(opcode: Int, message: String, characteristic: String)] {
        try requestLog(since: since).filter(\.isRequest).map {
            (opcode: ($0.opcode ?? -1) & 0xFF, message: $0.message ?? "", characteristic: $0.characteristic ?? "")
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

        /// The host takes a manager made with `attachDelegate: false`, as a setup flow hands it over:
        /// delegate, then queue, Trio's order.
        func adoptByHost() {
            manager.pumpManagerDelegate = delegate
            manager.delegateQueue = delegateQueue
            drainDelegate()
        }

        var bolusEvents: [NewPumpEvent] {
            drainDelegate()
            return delegate.pumpEvents.filter { $0.dose?.type == .bolus }
        }
    }

    /// A lost response and a failed connect are what several scenarios stage; at the production
    /// 30 s each they were most of the suite's run time. faketandem answers in well under a second.
    static let responseTimeout: TimeInterval = 2

    /// The reconnect retry's backoff: the production 5, 10, 20, 40, 60 s is wall-clock, which the manual clock
    /// cannot advance. The first delay leaves a test a second to re-arm a fault before the next attempt.
    static let reconnectRetryDelays: [TimeInterval] = [1, 2, 3, 4, 5]

    /// `clock` defaults to a ManualClock starting now, so a test can jump the driver's idea of time
    /// (bolus estimated end, sync throttles) without waiting; the emulator stays on its own clock.
    /// `poweredOnBeforeAttach` lands Bluetooth's poweredOn, and the connect attempts it queues, before the
    /// manager is attached to the Bluetooth manager, the order a relaunch on a phone can take.
    /// `via` reaches the emulator through something in between, such as `SecondClientProxy`.
    func makeDriver(
        state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:]),
        clock: TandemClock = ManualClock(Date()),
        attachDelegate: Bool = true,
        poweredOnBeforeAttach: Bool = false,
        via relay: SocketPumpEndpoint? = nil
    ) -> Driver {
        VirtualPump.endpoint = relay ?? endpoint
        VirtualPump.scanInterval = 0.5
        VirtualPump.responseTimeout = .milliseconds(Int(Self.responseTimeout * 1000))
        VirtualPump.connectTimeout = .seconds(15)
        VirtualPump.historyPacing = HistoryLogFetcher.Pacing(requestDelay: 0.05, pollInterval: 0.05, chunkTimeout: 2)
        // A live quick bolus button makes every sync wait for its history pass (`awaitsHistoryBoluses`); tests that exercise it set the flag.
        var state = state
        if !state.featureFlags.isOverridden(.quickBolusButtonSupport) {
            state.featureFlags[.quickBolusButtonSupport] = false
        }
        let bluetooth = TandemBluetoothManager()
        bluetooth.reconnectRetryDelays = Self.reconnectRetryDelays
        let central = bluetooth.manager!
        if poweredOnBeforeAttach {
            bluetooth.handleBluetoothStateChange(.poweredOn)
            // Queued behind any connect poweredOn started, so it returns once they have given up.
            let drained = DispatchSemaphore(value: 0)
            bluetooth.ensureConnected { _ in drained.signal() }
            _ = drained.wait(timeout: .now() + 30)
        }
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        let delegate = MockPumpManagerDelegate()
        // Before the delegate is attached: attaching fires the first callbacks synchronously, and
        // every journal entry should carry the driver's clock.
        delegate.journalClock = clock
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

    /// The app goes away with the pump still its own, as on a relaunch: stops the driver's
    /// auto-reconnect, drops the link and waits for the pump to see it go, so the next test's driver is
    /// not refused as `busy`. The host is told nothing.
    func shutDown(_ driver: Driver, timeout: TimeInterval = 40) throws {
        try tearDown(timeout: timeout) { done in
            driver.bluetooth.deactivate()
            done()
        }
    }

    /// The host deletes the pump manager: `delete()`, as Loop and Trio call it.
    func deactivate(_ driver: Driver, timeout: TimeInterval = 40) throws {
        try tearDown(timeout: timeout) { done in
            Task {
                await driver.manager.delete()
                done()
            }
        }
    }

    private func tearDown(timeout: TimeInterval, _ body: @escaping (@escaping () -> Void) -> Void) throws {
        let done = ResultBox<Bool>()
        // Both write DisconnectPumpRequest synchronously on the caller's thread.
        DispatchQueue.global().async {
            body { done.set(true) }
        }
        _ = try done.wait("driver teardown", timeout: timeout)
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

    /// How a driver gets its first authenticated session.
    enum PairingMethod {
        /// The onboarding flow: pairing code in, full JPAKE rounds 1a/1b/2/3/4 through pumpX2's
        /// jpake-server on the emulator side.
        case fresh
        /// The state after a completed pairing, staged directly: the same random long-term key is
        /// given to the pump (`setLongTermKey`) and to the driver (`pumpState.derivedSecret`), so the
        /// connect authenticates through the quick-reconnect rounds 3/4 alone. This is the emulator's
        /// pure-Go path: no jpake-server subprocess, so it is also the fast one.
        case seededLongTermKey
    }

    /// The method the flow tests use when pairing is a precondition rather than the subject.
    static let defaultPairingMethod: PairingMethod = .seededLongTermKey

    /// Stages a completed pairing on both sides without talking to the pump. The driver still has to
    /// connect and run rounds 3/4 to get a session.
    func seedLongTermKey(_ driver: Driver, peripheralId: UUID) throws -> Data {
        var key = Data(count: 32)
        key.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            for offset in 0 ..< buffer.count {
                base.storeBytes(of: UInt8.random(in: .min ... .max), toByteOffset: offset, as: UInt8.self)
            }
        }
        let status = try control.setLongTermKey(key)
        precondition(status.longTermKey == key, "emulator did not take the seeded key: \(status)")
        driver.manager.state.pumpState.derivedSecret = key
        driver.manager.state.pumpState.pincode = Self.pairingCode
        driver.manager.state.pumpState.peripheralUuid = peripheralId.uuidString
        return key
    }

    /// Discover + pair; throws if pairing fails.
    @discardableResult
    func pair(
        _ driver: Driver,
        method: PairingMethod = FaketandemHarness.defaultPairingMethod,
        timeout: TimeInterval = 90
    ) throws -> TandemPumpScan {
        let scan = try discover(driver)
        if method == .seededLongTermKey {
            _ = try seedLongTermKey(driver, peripheralId: scan.peripheral.identifier)
        }
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
