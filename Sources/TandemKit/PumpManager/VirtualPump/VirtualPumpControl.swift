#if TANDEMKIT_VIRTUAL_PUMP
import Foundation
import LoopKit

/// A test's handle on the driver inside a host app (Trio in the simulator), over a socket on
/// 127.0.0.1. The test makes the calls the host and its onboarding screens make, the host's own
/// delegate receives what the driver reports, and the test reads back every batch it was sent and
/// when the host finished with it. Only in the virtual pump build, whose Bluetooth is faketandem's
/// socket, so nothing sent here can reach a real pump.
///
/// One JSON `Request` per line, answered by one `Response` line, in order, per connection.
enum VirtualPumpControl {
    /// The loopback port to listen on, read from the host app's environment.
    static let environmentVariable = "TANDEMKIT_VIRTUAL_PUMP_CONTROL"

    static var port: UInt16? = ProcessInfo.processInfo.environment[environmentVariable].flatMap { UInt16($0) }

    private static let logger = TandemLogger(category: "VirtualPumpControl")
    private static let lock = NSLock()
    private static weak var latestManager: TandemPumpManager?
    private static var server: Server?
    private static var logs: [ObjectIdentifier: [Batch]] = [:]
    /// Per manager; a test reads a few dozen.
    private static let maximumLoggedBatches = 1000

    // MARK: - Hooks in TandemPumpManager

    /// The host's latest manager is the one commands reach. Starts listening on the first call when
    /// the environment names a port.
    static func attach(_ manager: TandemPumpManager) {
        lock.lock()
        defer { lock.unlock() }
        latestManager = manager
        logs[ObjectIdentifier(manager)] = []
        guard server == nil, let port else {
            return
        }
        do {
            server = try Server(port: port) { current }
            logger.warning("Virtual pump control listening on 127.0.0.1:\(port)")
        } catch {
            logger.error("Virtual pump control could not listen on 127.0.0.1:\(port): \(error)")
        }
    }

    /// From `prepareForDeactivation`: the host is letting `manager` go, so no command reaches it
    /// again, whether or not something still holds it.
    static func detach(_ manager: TandemPumpManager) {
        lock.lock()
        defer { lock.unlock() }
        if latestManager === manager {
            latestManager = nil
        }
    }

    /// The manager commands reach: the host's latest, until it is deleted.
    static var current: TandemPumpManager? {
        lock.lock()
        defer { lock.unlock() }
        return latestManager
    }

    /// Called as a batch goes to the delegate; returns the index `delegateDidFinish` takes.
    static func willDeliver(
        _ events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        hostNow: Date,
        from manager: TandemPumpManager
    ) -> Int {
        let batch = Batch(
            index: 0,
            hostNow: hostNow,
            lastReconciliation: lastReconciliation,
            replacePendingEvents: replacePendingEvents,
            events: events.map(Event.init),
            completed: false,
            delegateError: nil
        )
        lock.lock()
        defer { lock.unlock() }
        var log = logs[ObjectIdentifier(manager)] ?? []
        let index = (log.last?.index ?? -1) + 1
        log.append(Batch(copying: batch, index: index))
        if log.count > maximumLoggedBatches {
            log.removeFirst(log.count - maximumLoggedBatches)
        }
        logs[ObjectIdentifier(manager)] = log
        return index
    }

    /// The host's completion for batch `index`.
    static func delegateDidFinish(_ index: Int, error: Error?, from manager: TandemPumpManager) {
        lock.lock()
        defer { lock.unlock() }
        guard var log = logs[ObjectIdentifier(manager)],
              let position = log.firstIndex(where: { $0.index == index })
        else {
            return
        }
        log[position].completed = true
        log[position].delegateError = error.map { String(describing: $0) }
        logs[ObjectIdentifier(manager)] = log
    }

    static func batches(of manager: TandemPumpManager, after index: Int?) -> [Batch] {
        lock.lock()
        defer { lock.unlock() }
        return (logs[ObjectIdentifier(manager)] ?? []).filter { $0.index > (index ?? -1) }
    }

    // MARK: - Wire format

    struct Request: Codable, Equatable {
        enum Command: String, Codable {
            /// Nothing else; answers with `status`.
            case status
            /// Scan, then `pairPump(code:peripheral:)` with the first pump seen, as the scan screen
            /// does. With `longTermKey` (hex), the driver takes that key as a completed pairing's
            /// first, so only the quick-reconnect rounds run; the test gives faketandem the same one.
            case pair
            /// `applyOnboardingSettings`, as setup does once paired, with the settings the host
            /// gave the setup screen, which a seeded state stands in for.
            case applyOnboardingSettings
            /// `enactBolus(decisionId:units:activationType:)`, `automatic` choosing the activation type.
            case bolus
            /// `cancelBolus`, as the bolus progress screen's cancel does.
            case cancelBolus
            /// `syncPumpData`, as a pull to refresh does; answers with `lastSync`.
            case sync
            /// `syncBasalRateSchedule(items:)` with `basalSchedule`, as saving the basal profile does.
            case syncBasalSchedule
            /// `syncPumpTime`, as the settings screen's Sync Time does: the pump's clock to the phone's.
            case syncPumpTime
            /// `enactTempBasal(decisionId:unitsPerHour:for:)`; a `duration` of 0 cancels, as hosts cancel.
            case tempBasal
            case suspend
            case resume
            /// `recordCartridgeChange`, `recordTubingFill` and `recordSiteChange(primeAmount:)` with
            /// `units`: what the cartridge, fill tubing and fill cannula wizards report once the pump
            /// has done its part.
            case recordCartridgeChange
            case recordTubingFill
            case recordSiteChange
            /// `setFeatureFlag(_:enabled:)` with `featureFlag` and `enabled`, as the flags screen does.
            case setFeatureFlag
            /// `prepareForDeactivation`, as the settings screen's remove does: the driver drops its link
            /// and the host is told to let the manager go. Nothing sent afterwards reaches it.
            case deletePumpManager
            /// Every batch sent to the delegate after index `after`.
            case pumpEventBatches
        }

        var id: Int = 0
        var command: Command
        var code: String?
        var longTermKey: String?
        var units: Double?
        var automatic: Bool?
        var after: Int?
        var unitsPerHour: Double?
        /// Seconds.
        var duration: TimeInterval?
        var basalSchedule: [RepeatingScheduleValue<Double>]?
        var featureFlag: String?
        var enabled: Bool?
    }

    struct Response: Codable, Equatable {
        var id: Int
        var error: String?
        var status: Status?
        var lastSync: Date?
        var batches: [Batch]?
    }

    struct Status: Codable, Equatable {
        var onboarded: Bool
        var connected: Bool
        var delegateAttached: Bool
    }

    struct Batch: Codable, Equatable {
        var index: Int
        /// The driver's clock when the batch went out.
        var hostNow: Date
        var lastReconciliation: Date?
        var replacePendingEvents: Bool
        var events: [Event]
        /// The host called the completion; until then it may still be storing the batch.
        var completed: Bool
        var delegateError: String?

        init(
            index: Int,
            hostNow: Date,
            lastReconciliation: Date?,
            replacePendingEvents: Bool,
            events: [Event],
            completed: Bool,
            delegateError: String?
        ) {
            self.index = index
            self.hostNow = hostNow
            self.lastReconciliation = lastReconciliation
            self.replacePendingEvents = replacePendingEvents
            self.events = events
            self.completed = completed
            self.delegateError = delegateError
        }

        fileprivate init(copying batch: Batch, index: Int) {
            self = batch
            self.index = index
        }

        var pumpEvents: [NewPumpEvent] {
            events.map(\.pumpEvent)
        }
    }

    /// LoopKit's `NewPumpEvent` and `PumpEventType` are not `Codable`; `DoseEntry` and
    /// `PumpAlarmType` are. A marker (cartridge, site change, alarm) has no dose to name its type.
    struct Event: Codable, Equatable {
        var date: Date
        var raw: Data
        var title: String
        var dose: DoseEntry?
        var type: EventType?
        var alarmType: PumpAlarmType?

        init(_ event: NewPumpEvent) {
            date = event.date
            raw = event.raw
            title = event.title
            dose = event.dose
            type = event.type.flatMap(EventType.init)
            alarmType = event.alarmType
        }

        var pumpEvent: NewPumpEvent {
            NewPumpEvent(date: date, dose: dose, raw: raw, title: title, type: type?.pumpEventType, alarmType: alarmType)
        }
    }

    enum EventType: String, Codable {
        case alarm, alarmClear, basal, bolus, prime, resume, rewind, suspend, tempBasal
        case replaceReservoir, replacePump, replaceInfusionSet

        /// Nil for a time zone sync, which the driver never reports.
        init?(_ type: PumpEventType) {
            switch type {
            case .alarm: self = .alarm
            case .alarmClear: self = .alarmClear
            case .basal: self = .basal
            case .bolus: self = .bolus
            case .prime: self = .prime
            case .resume: self = .resume
            case .rewind: self = .rewind
            case .suspend: self = .suspend
            case .tempBasal: self = .tempBasal
            case .replaceComponent(componentType: .reservoir): self = .replaceReservoir
            case .replaceComponent(componentType: .pump): self = .replacePump
            case .replaceComponent(componentType: .infusionSet): self = .replaceInfusionSet
            case .timeZoneSync: return nil
            }
        }

        var pumpEventType: PumpEventType {
            switch self {
            case .alarm: .alarm
            case .alarmClear: .alarmClear
            case .basal: .basal
            case .bolus: .bolus
            case .prime: .prime
            case .resume: .resume
            case .rewind: .rewind
            case .suspend: .suspend
            case .tempBasal: .tempBasal
            case .replaceReservoir: .replaceComponent(componentType: .reservoir)
            case .replacePump: .replaceComponent(componentType: .pump)
            case .replaceInfusionSet: .replaceComponent(componentType: .infusionSet)
            }
        }
    }

    // MARK: - Server

    final class Server {
        private let listener: SocketListener
        var port: UInt16 { listener.port }

        init(port: UInt16 = 0, manager: @escaping () -> TandemPumpManager?) throws {
            listener = try SocketListener(port: port, name: "VirtualPumpControl") { link in
                Server.serve(link, manager: manager)
            }
        }

        func stop() {
            listener.stop()
        }

        private static func serve(_ link: SocketLink, manager: () -> TandemPumpManager?) {
            defer { link.close() }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            while let line = try? link.readLine(timeout: nil) {
                let response: Response
                do {
                    let request = try decoder.decode(Request.self, from: line)
                    response = handle(request, manager: manager())
                } catch {
                    response = Response(id: -1, error: "bad request: \(error)")
                }
                guard let data = try? encoder.encode(response), (try? link.send(line: data)) != nil else {
                    return
                }
            }
        }

        static func handle(_ request: Request, manager: TandemPumpManager?) -> Response {
            var response = Response(id: request.id)
            guard let manager else {
                response.error = "no TandemPumpManager to reach: none created, or the host deleted the last one"
                return response
            }
            do {
                switch request.command {
                case .status:
                    break
                case .pair:
                    try pair(manager, code: request.code, longTermKey: request.longTermKey)
                case .applyOnboardingSettings:
                    try applyOnboardingSettings(manager)
                case .bolus:
                    try bolus(manager, units: request.units, automatic: request.automatic ?? false)
                case .cancelBolus:
                    try cancelBolus(manager)
                case .sync:
                    response.lastSync = try sync(manager)
                case .syncBasalSchedule:
                    try syncBasalSchedule(manager, items: request.basalSchedule)
                case .syncPumpTime:
                    try syncPumpTime(manager)
                case .tempBasal:
                    try tempBasal(manager, unitsPerHour: request.unitsPerHour, duration: request.duration)
                case .suspend:
                    try deliveryChange("suspendDelivery") { manager.suspendDelivery(completion: $0) }
                case .resume:
                    try deliveryChange("resumeDelivery") { manager.resumeDelivery(completion: $0) }
                case .recordCartridgeChange:
                    manager.recordCartridgeChange()
                case .recordTubingFill:
                    manager.recordTubingFill()
                case .recordSiteChange:
                    manager.recordSiteChange(primeAmount: request.units)
                case .setFeatureFlag:
                    try setFeatureFlag(manager, name: request.featureFlag, enabled: request.enabled)
                case .deletePumpManager:
                    try deletePumpManager(manager)
                case .pumpEventBatches:
                    response.batches = VirtualPumpControl.batches(of: manager, after: request.after)
                }
            } catch {
                response.error = String(describing: error)
            }
            response.status = Status(
                onboarded: manager.isOnboarded,
                connected: manager.state.isConnected,
                delegateAttached: manager.pumpManagerDelegate != nil
            )
            return response
        }

        private static func pair(_ manager: TandemPumpManager, code: String?, longTermKey: String?) throws {
            guard let code else {
                throw ControlError("pair needs a code")
            }
            let key = try longTermKey.map { hex -> Data in
                guard let key = Data(hexadecimalString: hex) else {
                    throw ControlError("longTermKey is not hex")
                }
                return key
            }
            let scan = Completion<TandemPumpScan>()
            // The central reports powered-on asynchronously after it is created.
            let deadline = Date().addingTimeInterval(10)
            while !manager.bluetooth.startScan({ scan.finish($0) }) {
                guard Date() < deadline else {
                    throw ControlError("Bluetooth never powered on")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            let found = try scan.wait("an advertisement", timeout: 30)
            manager.bluetooth.stopScan()
            if let key {
                manager.state.pumpState.derivedSecret = key
                manager.state.pumpState.peripheralUuid = found.peripheral.identifier.uuidString
            }
            let paired = Completion<Error?>()
            manager.pairPump(code: code, peripheral: found.peripheral) { paired.finish($0) }
            if let error = try paired.wait("pairPump", timeout: 180) {
                throw error
            }
        }

        private static func bolus(_ manager: TandemPumpManager, units: Double?, automatic: Bool) throws {
            guard let units else {
                throw ControlError("bolus needs units")
            }
            let enacted = Completion<PumpManagerError?>()
            manager.enactBolus(decisionId: nil, units: units, activationType: automatic ? .automatic : .manualNoRecommendation) {
                enacted.finish($0)
            }
            if let error = try enacted.wait("enactBolus", timeout: 120) {
                throw error
            }
        }

        private static func applyOnboardingSettings(_ manager: TandemPumpManager) throws {
            let applied = Completion<OnboardingSettingsFailure?>()
            manager.applyOnboardingSettings { applied.finish($0) }
            if let failure = try applied.wait("applyOnboardingSettings", timeout: 240) {
                let basal = failure.basalSchedule.map { String(describing: $0) } ?? "written"
                let limits = failure.deliveryLimits.map { String(describing: $0) } ?? "written"
                throw ControlError("applyOnboardingSettings: basal schedule \(basal), delivery limits \(limits)")
            }
        }

        private static func cancelBolus(_ manager: TandemPumpManager) throws {
            let cancelled = Completion<PumpManagerResult<DoseEntry?>>()
            manager.cancelBolus { cancelled.finish($0) }
            if case let .failure(error) = try cancelled.wait("cancelBolus", timeout: 120) {
                throw error
            }
        }

        private static func setFeatureFlag(_ manager: TandemPumpManager, name: String?, enabled: Bool?) throws {
            guard let name, let enabled else {
                throw ControlError("setFeatureFlag needs featureFlag and enabled")
            }
            guard let flag = TandemFeatureFlags.Flag(rawValue: name) else {
                throw ControlError("no feature flag \(name)")
            }
            manager.setFeatureFlag(flag, enabled: enabled)
        }

        private static func deletePumpManager(_ manager: TandemPumpManager) throws {
            let deleted = Completion<Error?>()
            manager.prepareForDeactivation { deleted.finish($0) }
            if let error = try deleted.wait("prepareForDeactivation", timeout: 120) {
                throw error
            }
        }

        private static func sync(_ manager: TandemPumpManager) throws -> Date? {
            let synced = Completion<Date?>()
            manager.syncPumpData { synced.finish($0) }
            return try synced.wait("syncPumpData", timeout: 240)
        }

        private static func syncPumpTime(_ manager: TandemPumpManager) throws {
            let synced = Completion<Result<Void, PumpManagerError>>()
            manager.syncPumpTime { synced.finish($0) }
            try synced.wait("syncPumpTime", timeout: 240).get()
        }

        private static func syncBasalSchedule(_ manager: TandemPumpManager, items: [RepeatingScheduleValue<Double>]?) throws {
            guard let items else {
                throw ControlError("syncBasalSchedule needs basalSchedule")
            }
            let synced = Completion<Result<BasalRateSchedule, Error>>()
            manager.syncBasalRateSchedule(items: items) { synced.finish($0) }
            _ = try synced.wait("syncBasalRateSchedule", timeout: 240).get()
        }

        private static func tempBasal(_ manager: TandemPumpManager, unitsPerHour: Double?, duration: TimeInterval?) throws {
            guard let unitsPerHour, let duration else {
                throw ControlError("tempBasal needs unitsPerHour and duration")
            }
            let enacted = Completion<PumpManagerError?>()
            manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: duration) { enacted.finish($0) }
            if let error = try enacted.wait("enactTempBasal", timeout: 120) {
                throw error
            }
        }

        private static func deliveryChange(_ name: String, _ command: (@escaping (Error?) -> Void) -> Void) throws {
            let changed = Completion<Error?>()
            command { changed.finish($0) }
            if let error = try changed.wait(name, timeout: 120) {
                throw error
            }
        }
    }

    /// The test's end: one request at a time, a refusal thrown as `ControlError`.
    final class Client {
        private let link: SocketLink
        private var nextId = 1

        init(port: UInt16) throws {
            link = try SocketLink(connectTo: SocketPumpEndpoint(host: "127.0.0.1", port: port))
        }

        @discardableResult
        func send(_ request: Request, timeout: TimeInterval = 300) throws -> Response {
            var request = request
            request.id = nextId
            nextId += 1
            try link.send(line: JSONEncoder().encode(request))
            guard let line = try link.readLine(timeout: timeout) else {
                throw ControlError("the control channel closed")
            }
            let response = try JSONDecoder().decode(Response.self, from: line)
            if let error = response.error {
                throw ControlError(error)
            }
            return response
        }

        func close() {
            link.shutdown()
            link.close()
        }
    }

    struct ControlError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    /// The first value a callback delivers, waited for on the connection's own thread.
    private final class Completion<Value> {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var value: Value?

        func finish(_ value: Value) {
            lock.lock()
            defer { lock.unlock() }
            guard self.value == nil else {
                return
            }
            self.value = value
            done.signal()
        }

        func wait(_ what: String, timeout: TimeInterval) throws -> Value {
            guard done.wait(timeout: .now() + timeout) == .success else {
                throw ControlError("timed out after \(Int(timeout)) s waiting for \(what)")
            }
            lock.lock()
            defer { lock.unlock() }
            return value!
        }
    }
}

extension VirtualPumpControl.Response {
    init(id: Int, error: String? = nil) {
        self.init(id: id, error: error, status: nil, lastSync: nil, batches: nil)
    }
}
#endif
