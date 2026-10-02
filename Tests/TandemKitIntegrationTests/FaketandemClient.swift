import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The faketandem control API (README.md "Integration harness API" and pkg/api). Everything here is
// synchronous: the tests drive the pump from the test thread and poll for the driver's reaction.

enum FaketandemClientError: Error, CustomStringConvertible {
    case http(status: Int, path: String, body: String)
    case transport(String)
    case decoding(String)

    var description: String {
        switch self {
        case let .http(status, path, body):
            return "HTTP \(status) from \(path): \(body)"
        case let .transport(message):
            return "transport error: \(message)"
        case let .decoding(message):
            return "decoding error: \(message)"
        }
    }
}

enum FaketandemPairingState: String, Codable {
    case notDiscoverable = "NotDiscoverable"
    case discoverableOnly = "DiscoverableOnly"
    case pairStep1 = "PairStep1"
    case pairStep2 = "PairStep2"

    /// The last manufacturer-data byte the pump advertises in this state.
    var manufacturerByte: UInt8 {
        switch self {
        case .notDiscoverable, .discoverableOnly: return 0x10
        case .pairStep1: return 0x11
        case .pairStep2: return 0x12
        }
    }
}

/// One history-log record as the harness API reports it (`pkg/harness/history.go`
/// `historyEntrySnapshot`).
///
/// The two timestamps are not two renderings of one number:
///
/// - `time` is the record's **true instant** on the pump's Clock, with neither the pump's clock
///   skew nor its time zone folded in;
/// - `pumpSeconds` is the same instant **as it went on the wire**: pump-epoch seconds with both
///   the skew (`pump_offset_seconds`) and the pump's zone (`pump_timezone_offset_seconds`)
///   applied. `pumpTime` is that same value under the name the state snapshot has always used.
///
/// Either is derivable from the other with the two offsets `/api/clock` reports:
///
///     unix(time) = pumpSeconds + 1_199_145_600 - pumpTimezoneOffsetSeconds - pumpOffsetSeconds
///
/// `data` holds the record's own **wire fields**, named exactly as pumpX2 and TandemKit name them,
/// and nothing else. `extra` holds the pump-side context a 26-byte record has no room for — a temp
/// rate's delivered volume, the reason string behind a suspend, the alert type behind an alarm —
/// which never reaches the wire and is kept separate so it cannot be mistaken for a record field.
struct FaketandemHistoryEntry: Decodable {
    let sequence: Int
    let typeId: Int
    let type: String
    let time: Date
    let pumpSeconds: Int
    let pumpTime: Int
    let data: [String: FaketandemJSONValue]?
    let extra: [String: FaketandemJSONValue]?
    /// The high nibble of the record's type-id word (1 on Mobi captures, 0 on older ones).
    let sourceNibble: Int?
    /// How far `pumpSeconds` runs ahead of `time`, as the pump's clock was set when the record was
    /// written. nil from an emulator that predates clock setting.
    let wireOffsetSeconds: Int?

    /// The true instant the record's wire timestamp stands for.
    func instant(clock: FaketandemClock) -> Date {
        guard let wireOffsetSeconds else { return clock.instant(fromPumpSeconds: pumpSeconds) }
        return Date(timeIntervalSince1970: FaketandemClock.tandemEpochUnix + Double(pumpSeconds - wireOffsetSeconds))
    }
}

/// `GET /api/history?since=&limit=`, the full history feed. `since` is exclusive — the last
/// sequence the caller already has — so a poller hands back the previous page's `nextSince`
/// unchanged, and `truncated` says the limit cut the page short.
struct FaketandemHistoryPage: Decodable {
    let count: Int
    let firstSequence: Int
    let lastSequence: Int
    let since: Int
    let limit: Int
    let nextSince: Int
    let truncated: Bool
    let entries: [FaketandemHistoryEntry]
}

/// `GET /api/state`, the parts the tests read. Unknown keys are ignored so the emulator can grow.
struct FaketandemSnapshot: Decodable {
    struct Identity: Decodable {
        let serialNumber: String
        let model: String
        let apiVersionMajor: Int
        let apiVersionMinor: Int
    }

    typealias Clock = FaketandemClock

    struct Auth: Decodable {
        let authenticated: Bool
        let pairingCode: String
        let longTermKeyPresent: Bool
        let pairingState: FaketandemPairingState
    }

    struct Connection: Decodable {
        let connected: Bool
        let radioEnabled: Bool
    }

    struct Basal: Decodable {
        let profileRate: Double
        let currentRate: Double
        let suspended: Bool
        let suspendReason: String?
        let tempActive: Bool
        let tempRate: Double
        let tempPercent: Int
        /// Present only while a temp rate runs (the emulator omits zero times).
        let tempStart: FaketandemOptionalTime?
        let tempEnd: FaketandemOptionalTime?
        let tempRateId: Int?
        let tempStartPumpSeconds: Int?
    }

    struct Bolus: Decodable {
        let active: Bool
        let stalled: Bool
        let bolusId: Int
        let unitsTotal: Double
        let unitsDelivered: Double
        let sourceId: Int
        let typeBitmask: Int
        /// Present only while a bolus runs.
        let startTime: FaketandemOptionalTime?
        let startPumpSeconds: Int?
        let rateUnitsPerSecond: Double
    }

    struct LastBolus: Decodable {
        let bolusId: Int
        let requestedUnits: Double
        let deliveredUnits: Double
        let sourceId: Int
        let typeBitmask: Int
        let endReasonId: Int
        let endTime: Date
        let endPumpSeconds: Int
    }

    struct Insulin: Decodable {
        let reservoirUnits: Double
        let iob: Double
    }

    struct Battery: Decodable {
        let percentage: Int
        let charging: Bool
    }

    struct RequestLog: Decodable {
        let entries: Int
        let lastSeq: Int
    }

    /// A standing alert. `time` is the true instant it was raised on the pump's Clock;
    /// `pumpSeconds` is the same instant as the wire carries it.
    struct Alert: Decodable {
        let id: Int
        let type: Int
        let typeName: String
        let priority: Int
        let message: String
        let time: Date
        let pumpSeconds: Int
        let acknowledged: Bool
    }

    /// One entry of `alarms_history`: an alarm that was raised and has since been cleared, with
    /// both ends of the interval. `alerts` only ever reports what stands now, so this is the only
    /// place a timeline can read the clearing from.
    struct ClearedAlarm: Decodable {
        let id: Int
        let type: Int
        let typeName: String
        let priority: Int
        let message: String
        let time: Date
        let pumpSeconds: Int
        let clearedTime: Date
        let clearedPumpSeconds: Int
    }

    typealias HistoryEntry = FaketandemHistoryEntry

    /// The tail of the history log (the emulator's `historySnapshotLimit`, 50 records). A scenario
    /// that runs for a while loses records off the front of it without being told, so the timeline
    /// is built from `GET /api/history` instead; this stays for the sequence marks.
    struct History: Decodable {
        let count: Int
        let firstSequence: Int
        let lastSequence: Int
        /// The latest instant any record was written at; nil from an older emulator or an empty log.
        let latestTime: Date?
        let entries: [HistoryEntry]
    }

    let identity: Identity
    let clock: Clock
    let auth: Auth
    let connection: Connection
    let basal: Basal
    let bolus: Bolus
    let lastBolus: LastBolus?
    let insulin: Insulin
    let battery: Battery
    let alerts: [Alert]
    /// Every alarm that has been raised *and* cleared, with both ends (`alarms_history`).
    let alarmsHistory: [ClearedAlarm]
    /// The cartridge procedure the pump has open: `none`, `change_cartridge` or `fill_tubing`.
    let workflowMode: String?
    /// nil from an emulator that predates profile modelling.
    let idpProfiles: [FaketandemIDPProfile]?
    let history: History
    let requestLog: RequestLog
}

/// One insulin delivery profile, in the wire's units; slot 0 of `idp_profiles` is the active one.
struct FaketandemIDPProfile: Decodable, Equatable {
    struct Segment: Decodable, Equatable {
        /// Minutes after midnight, pump local time.
        let startTime: Int
        /// Milliunits per hour.
        let basalRate: Int
        var carbRatio: Int = 10000
        var targetBg: Int = 110
        var isf: Int = 50

        init(startTime: Int, basalRate: Int) {
            self.startTime = startTime
            self.basalRate = basalRate
        }

        var fields: [String: Any] {
            ["start_time": startTime, "basal_rate": basalRate, "carb_ratio": carbRatio, "target_bg": targetBg, "isf": isf]
        }
    }

    let id: Int
    var name: String = "Profile 1"
    var insulinDuration: Int = 300
    var maxBolus: Int = 25000
    var carbEntry: Bool = true
    let segments: [Segment]

    init(id: Int, segments: [Segment]) {
        self.id = id
        self.segments = segments
    }

    /// What a fresh emulator holds (`state.DefaultIDPProfiles`).
    static let emulatorDefault = FaketandemIDPProfile(id: 1, segments: [Segment(startTime: 0, basalRate: 850)])

    var fields: [String: Any] {
        [
            "id": id,
            "name": name,
            "insulin_duration": insulinDuration,
            "max_bolus": maxBolus,
            "carb_entry": carbEntry,
            "segments": segments.map(\.fields)
        ]
    }
}

/// An RFC 3339 time the emulator emits as an empty string (Go's `omitempty` on a formatted zero
/// time) when unset. Decodes to `nil` in that case instead of failing the whole snapshot.
struct FaketandemOptionalTime: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        if string.isEmpty {
            date = nil
        } else if let parsed = FaketandemClient.parseDate(string) {
            date = parsed
        } else {
            throw FaketandemClientError.decoding("unparseable time \(string)")
        }
    }
}

/// A JSON value of unknown shape, for the free-form `data` maps on history records.
enum FaketandemJSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([FaketandemJSONValue])
    case object([String: FaketandemJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([FaketandemJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: FaketandemJSONValue].self) {
            self = .object(object)
        } else {
            throw FaketandemClientError.decoding("unsupported JSON value")
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .number(value): return value
        case let .string(string): return Double(string)
        case let .bool(bool): return bool ? 1 : 0
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case let .number(value): return Int(value)
        case let .string(string): return Int(string)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case let .string(string): return string
        case let .number(value): return String(value)
        case let .bool(bool): return String(bool)
        default: return nil
        }
    }
}

/// One `GET /api/log` entry. `kind` is request | response | notification | connection | fault.
struct FaketandemLogEntry: Decodable {
    let seq: Int
    let time: Date
    let kind: String
    let characteristic: String?
    let message: String?
    let opcode: Int?
    let txId: Int?
    let fragments: [String]?
    let fragmentsSent: Int?
    let note: String?
    let connected: Bool?
    let fault: String?
    /// The parsed request's fields, under pumpX2's names.
    let cargo: [String: FaketandemJSONValue]?

    var isRequest: Bool { kind == "request" }
    var isResponse: Bool { kind == "response" }
}

struct FaketandemLog: Decodable {
    let entries: [FaketandemLogEntry]
    let oldestSeq: Int
    let lastSeq: Int
}

/// `GET|PUT /api/transport`: the link parameters that are not pump state. The ATT MTU decides how
/// responses are framed — at the 23-byte default every notification carries 20 bytes (18 of
/// message), the framing pumpX2's `Packetize` and the cliparser jar produce; a real Mobi over iOS
/// negotiates a much larger one, so most responses arrive as a single notification.
struct FaketandemTransport: Decodable {
    let attMtu: Int
    /// Bytes one notification can carry at that MTU (MTU minus the 3-byte ATT header).
    let maxNotificationBytes: Int
    /// Message bytes that leaves after the 2-byte `[remaining][txId]` framing. A response whose
    /// body fits in this many bytes goes out in one notification.
    let maxMessageBytesPerNotification: Int
    /// False on the Linux GATT transport, which lets gatt negotiate the MTU and never reports it.
    let mtuConfigurable: Bool
}

/// `GET|PUT /api/clock`. Two separate offsets sit between the emulator's clock and the wire, and
/// they mean different things (README "Clock"):
///
/// - `pumpTimezone` / `pumpTimezoneOffsetSeconds` is the pump's **local-time convention**, not a
///   lie. A Tandem pump keeps its clock in local time with no zone attached, and every consumer
///   decodes on that assumption (TandemKit's `Dates.fromJan12008ToUnixEpochSeconds` subtracts
///   `TimeZone.current.secondsFromGMT()`), so the emulator encodes with the zone's offset added.
///   The offset is read-only: the zone's offset in force at `pumpNow`, so a caller never has to
///   work out which side of a DST transition the pump is on.
/// - `pumpOffsetSeconds` is a **skew**: a lie the pump tells about the time, stacked on top of the
///   zone, which moves every wire timestamp without touching delivery arithmetic.
struct FaketandemClock: Decodable {
    let mode: String
    let now: Date
    let pumpOffsetSeconds: Double
    /// The IANA zone the pump keeps its clock in ("America/New_York"); "UTC" turns the convention off.
    let pumpTimezone: String
    /// That zone's UTC offset in force at `pumpNow`, read-only.
    let pumpTimezoneOffsetSeconds: Int
    let frozen: Bool
    let pumpNow: Date
    let pumpTimeSeconds: Int
    let timeSinceReset: Int

    /// The true instant a wire timestamp of `pumpSeconds` meant, with both offsets removed.
    func instant(fromPumpSeconds pumpSeconds: Int) -> Date {
        Date(
            timeIntervalSince1970: FaketandemClock.tandemEpochUnix + Double(pumpSeconds)
                - Double(pumpTimezoneOffsetSeconds) - pumpOffsetSeconds
        )
    }

    /// 2008-01-01T00:00:00Z, the Tandem pump epoch (`pkg/state/pumptime.go` `tandemEpochUnix`).
    static let tandemEpochUnix: TimeInterval = 1_199_145_600
}

struct FaketandemFault: Decodable {
    let id: Int
    let kind: String
    let message: String?
    let count: Int?
    let fired: Int?
}

/// A `POST /api/faults` body. Leave `message`/`opcode`/`characteristic` nil to hit the next message
/// of any kind.
struct FaketandemFaultSpec {
    enum Kind: String {
        case dropResponse = "drop_response"
        case delayResponse = "delay_response"
        case errorResponse = "error_response"
        case disconnect
        case rejectQuickPair = "reject_quick_pair"
        case radioOff = "radio_off"
        case radioOn = "radio_on"
    }

    var kind: Kind
    var message: String?
    var opcode: Int?
    var characteristic: String?
    var count: Int?
    var every: Bool?
    var delayMilliseconds: Int?
    var errorCode: Int?
    /// `request` or `partial_response`, for `.disconnect`.
    var after: String?
    var fragmentsSent: Int?

    init(_ kind: Kind, message: String? = nil) {
        self.kind = kind
        self.message = message
    }

    var body: [String: Any] {
        var body: [String: Any] = ["kind": kind.rawValue]
        if let message { body["message"] = message }
        if let opcode { body["opcode"] = opcode }
        if let characteristic { body["characteristic"] = characteristic }
        if let count { body["count"] = count }
        if let every { body["every"] = every }
        if let delayMilliseconds { body["delay_ms"] = delayMilliseconds }
        if let errorCode { body["error_code"] = errorCode }
        if let after { body["after"] = after }
        if let fragmentsSent { body["fragments_sent"] = fragmentsSent }
        return body
    }
}

final class FaketandemClient {
    let apiBaseURL: URL
    private let session: URLSession
    private let requestTimeout: TimeInterval
    private let decoder: JSONDecoder

    init(apiBaseURL: URL, requestTimeout: TimeInterval = 10) {
        self.apiBaseURL = apiBaseURL
        self.requestTimeout = requestTimeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.parseDate(string) {
                return date
            }
            throw FaketandemClientError.decoding("unparseable date \(string)")
        }
    }

    /// Go's RFC 3339 output has variable fractional-second precision and may carry a zone offset.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? wholeSecondFormatter.date(from: string)
    }

    // MARK: - Pairing state (advertisement)

    func pairingState() throws -> FaketandemPairingState {
        struct Body: Decodable { let pairingState: FaketandemPairingState }
        return try get("/api/bluetooth/pairingstate", as: Body.self).pairingState
    }

    func setPairingState(_ state: FaketandemPairingState) throws {
        _ = try send("POST", "/api/bluetooth/pairingstate", json: ["pairingState": state.rawValue])
    }

    // MARK: - Snapshot and direct writes

    func snapshot() throws -> FaketandemSnapshot {
        try get("/api/state", as: FaketandemSnapshot.self)
    }

    /// `PUT /api/state`: sets the named fields and nothing else (no qualifying events, no history).
    @discardableResult
    func setState(_ fields: [String: Any]) throws -> FaketandemSnapshot {
        struct Body: Decodable {
            let applied: [String]
            let state: FaketandemSnapshot
        }
        let body = try decode(send("PUT", "/api/state", json: fields), as: Body.self)
        let missing = Set(fields.keys).subtracting(body.applied)
        guard missing.isEmpty else {
            throw FaketandemClientError.http(status: 200, path: "/api/state", body: "fields not applied: \(missing.sorted())")
        }
        return body.state
    }

    /// Replaces every profile on the pump, with none of the checks a request goes through.
    func setIDPProfiles(_ profiles: [FaketandemIDPProfile]) throws {
        try setState(["idp_profiles": profiles.map(\.fields)])
    }

    // MARK: - Clock

    func clock() throws -> FaketandemClock {
        try get("/api/clock", as: FaketandemClock.self)
    }

    /// `mode` is `manual` or `real`.
    @discardableResult
    func setClock(
        mode: String,
        now: Date? = nil,
        frozen: Bool? = nil,
        pumpOffsetSeconds: Double? = nil,
        pumpTimezone: String? = nil
    ) throws -> FaketandemClock {
        var body: [String: Any] = ["mode": mode]
        if let now { body["now"] = Self.fractionalFormatter.string(from: now) }
        if let frozen { body["frozen"] = frozen }
        if let pumpOffsetSeconds { body["pump_offset_seconds"] = pumpOffsetSeconds }
        if let pumpTimezone { body["pump_timezone"] = pumpTimezone }
        return try decode(send("PUT", "/api/clock", json: body), as: FaketandemClock.self)
    }

    /// Manual mode only (409 otherwise). `ticks` splits the step so mid-step expiries happen in order.
    @discardableResult
    func advanceClock(seconds: Double, ticks: Int? = nil) throws -> FaketandemClock {
        var body: [String: Any] = ["seconds": seconds]
        if let ticks { body["ticks"] = ticks }
        return try decode(send("POST", "/api/clock/advance", json: body), as: FaketandemClock.self)
    }

    // MARK: - Pump-initiated actions (each returns the resulting snapshot)

    /// `source` is `pump` (default, source id 0) or `remote` (the app, source id 8).
    @discardableResult
    func startBolus(
        units: Double,
        durationSeconds: Double? = nil,
        rate: Double? = nil,
        bolusId: Int? = nil,
        source: String? = nil
    ) throws -> FaketandemSnapshot {
        var body: [String: Any] = ["units": units]
        if let durationSeconds { body["duration_seconds"] = durationSeconds }
        if let rate { body["rate"] = rate }
        if let bolusId { body["bolus_id"] = bolusId }
        if let source { body["source"] = source }
        return try action("/api/state/bolus/start", body)
    }

    @discardableResult
    func stallBolus() throws -> FaketandemSnapshot { try action("/api/state/bolus/stall") }

    @discardableResult
    func resumeBolus() throws -> FaketandemSnapshot { try action("/api/state/bolus/resume") }

    @discardableResult
    func abortBolus(deliveredUnits: Double? = nil) throws -> FaketandemSnapshot {
        try action("/api/state/bolus/abort", deliveredUnits.map { ["delivered_units": $0] } ?? [:])
    }

    @discardableResult
    func completeBolus() throws -> FaketandemSnapshot { try action("/api/state/bolus/complete") }

    @discardableResult
    func startTempBasal(percent: Int? = nil, rate: Double? = nil, durationMinutes: Int) throws -> FaketandemSnapshot {
        var body: [String: Any] = ["duration_minutes": durationMinutes]
        if let percent { body["percent"] = percent }
        if let rate { body["rate"] = rate }
        return try action("/api/state/tempbasal/start", body)
    }

    @discardableResult
    func stopTempBasal() throws -> FaketandemSnapshot { try action("/api/state/tempbasal/stop") }

    /// `reason` is `user`, `occlusion` or `alarm`.
    @discardableResult
    func suspend(reason: String = "user") throws -> FaketandemSnapshot {
        try action("/api/state/suspend", ["reason": reason])
    }

    @discardableResult
    func resume(clearAlarms: Bool? = nil) throws -> FaketandemSnapshot {
        try action("/api/state/resume", clearAlarms.map { ["clear_alarms": $0] } ?? [:])
    }

    /// Answers with the history tail, not a snapshot, so the snapshot is read back separately.
    @discardableResult
    func appendHistory(type: String, secondsAgo: Double, data: [String: Any]) throws -> FaketandemSnapshot {
        _ = try send("POST", "/api/state/history/append", json: ["type": type, "seconds_ago": secondsAgo, "data": data])
        return try snapshot()
    }

    /// Appends `records` (each `type`, `seconds_ago`, `data`) in order; returns their sequence numbers.
    @discardableResult
    func appendHistory(records: [[String: Any]]) throws -> ClosedRange<Int> {
        struct Body: Decodable {
            let firstSequence: Int
            let lastSequence: Int
        }
        let body = try decode(send("POST", "/api/state/history/bulk", json: ["records": records]), as: Body.self)
        return body.firstSequence ... body.lastSequence
    }

    /// Empties the pump's history log; the next record is sequence 1.
    func eraseHistory() throws {
        _ = try send("POST", "/api/state/history/erase", json: [:])
    }

    /// The pump's user sets its date and time on the pump: the clock moves by `deltaSeconds` and the
    /// pump writes `TimeChanged`/`DateChange` records; no connected driver is told. Returns the
    /// clock's wire reading before and after.
    @discardableResult
    func setPumpTimeOnThePump(deltaSeconds: TimeInterval) throws -> (prior: Int, after: Int) {
        struct Body: Decodable {
            let priorPumpSeconds: Int
            let pumpSeconds: Int
        }
        let body = try decode(send("POST", "/api/state/time", json: ["delta_seconds": deltaSeconds]), as: Body.self)
        return (body.priorPumpSeconds, body.pumpSeconds)
    }

    /// Answers with the bitmask it raised, not a snapshot.
    @discardableResult
    func raiseQualifyingEvent(bitmask: UInt32) throws -> FaketandemSnapshot {
        _ = try send("POST", "/api/state/qualifyingevent", json: ["bitmask": Int(bitmask)])
        return try snapshot()
    }

    // MARK: - Link parameters (ATT MTU)

    /// The emulator's default (`-virtual-mtu`): the Bluetooth spec minimum, 20-byte notifications.
    static let defaultATTMTU = 23
    /// The order of MTU a real Mobi paired with the official iOS app negotiates.
    static let largeATTMTU = 247

    func transport() throws -> FaketandemTransport {
        try get("/api/transport", as: FaketandemTransport.self)
    }

    /// `PUT /api/transport`; 501 on a transport that does not expose its MTU.
    @discardableResult
    func setATTMTU(_ mtu: Int) throws -> FaketandemTransport {
        try decode(send("PUT", "/api/transport", json: ["att_mtu": mtu]), as: FaketandemTransport.self)
    }

    // MARK: - History log

    /// One page of `GET /api/history`. `since` is exclusive.
    func historyPage(since: Int? = nil, limit: Int? = nil) throws -> FaketandemHistoryPage {
        var query: [String] = []
        if let since { query.append("since=\(since)") }
        if let limit { query.append("limit=\(limit)") }
        let path = query.isEmpty ? "/api/history" : "/api/history?" + query.joined(separator: "&")
        return try get(path, as: FaketandemHistoryPage.self)
    }

    /// Every history record after `since`, following `next_since` until the feed stops truncating.
    /// This is what a timeline is built from: the 50-record tail in `GET /api/state` silently drops
    /// records off its front once a scenario has run for a while.
    func history(since: Int = 0, pageLimit: Int? = nil) throws -> [FaketandemHistoryEntry] {
        var entries: [FaketandemHistoryEntry] = []
        var cursor = since
        // Bounded: each page either advances the cursor or ends the loop, and the emulator caps a
        // page at 5000 records, so this cannot spin on a stuck feed.
        for _ in 0 ..< 64 {
            let page = try historyPage(since: cursor, limit: pageLimit)
            entries.append(contentsOf: page.entries)
            guard page.truncated, page.nextSince > cursor else { break }
            cursor = page.nextSince
        }
        return entries
    }

    // MARK: - Request log

    func requestLog(since: Int? = nil) throws -> FaketandemLog {
        try get(since.map { "/api/log?since=\($0)" } ?? "/api/log", as: FaketandemLog.self)
    }

    func clearRequestLog() throws {
        _ = try send("DELETE", "/api/log")
    }

    // MARK: - Faults

    func faults() throws -> [FaketandemFault] {
        struct Body: Decodable { let faults: [FaketandemFault] }
        return try get("/api/faults", as: Body.self).faults
    }

    @discardableResult
    func armFault(_ spec: FaketandemFaultSpec) throws -> FaketandemFault? {
        struct Body: Decodable { let fault: FaketandemFault? }
        return try decode(send("POST", "/api/faults", json: spec.body), as: Body.self).fault
    }

    func clearFault(id: Int) throws {
        _ = try send("DELETE", "/api/faults/\(id)")
    }

    func clearFaults() throws {
        _ = try send("DELETE", "/api/faults")
    }

    // MARK: - Settings table (the pre-harness constant-response configuration)

    /// `GET /api/settings/{messageType}`; the `value` map is what a constant-mode response carries.
    func settingsValue(for messageType: String) throws -> [String: Any] {
        let data = try send("GET", "/api/settings/\(messageType)")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FaketandemClientError.decoding("settings for \(messageType) is not an object")
        }
        return object["value"] as? [String: Any] ?? [:]
    }

    // MARK: - Plumbing

    /// Every pump-initiated action answers `{"state": <snapshot>}` (`pkg/harness/actions.go`
    /// `writeJSON(w, http.StatusOK, map[string]interface{}{"state": h.Snapshot()})`), so the
    /// snapshot is unwrapped rather than decoded from the body directly.
    private struct ActionEnvelope: Decodable {
        let state: FaketandemSnapshot
    }

    private func action(_ path: String, _ body: [String: Any] = [:]) throws -> FaketandemSnapshot {
        try decode(send("POST", path, json: body), as: ActionEnvelope.self).state
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
        try decode(send("GET", path), as: type)
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw FaketandemClientError.decoding("\(error): \(String(decoding: data, as: UTF8.self))")
        }
    }

    @discardableResult
    func send(_ method: String, _ path: String, json: [String: Any]? = nil) throws -> Data {
        guard let url = URL(string: path, relativeTo: apiBaseURL) else {
            throw FaketandemClientError.transport("bad path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let box = ResultBox<Result<(Data, HTTPURLResponse), Error>>()
        session.dataTask(with: request) { data, response, error in
            if let error {
                box.set(.failure(error))
            } else if let response = response as? HTTPURLResponse {
                box.set(.success((data ?? Data(), response)))
            } else {
                box.set(.failure(FaketandemClientError.transport("no HTTP response")))
            }
        }.resume()

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try box.wait("\(method) \(path)", timeout: requestTimeout + 5).get()
        } catch let error as FaketandemClientError {
            throw error
        } catch {
            throw FaketandemClientError.transport("\(method) \(path): \(error)")
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw FaketandemClientError.http(
                status: response.statusCode,
                path: path,
                body: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return data
    }
}
