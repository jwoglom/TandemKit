import Foundation
import TandemCore

// MARK: - Transport Protocol

/// Abstraction for packet transport layer (BLE or mock)
protocol SimulatorTransport: AnyObject {
    /// Start the transport layer and begin accepting connections
    func start() async throws

    /// Stop the transport layer
    func stop() async throws

    /// Read a packet from the specified characteristic
    /// - Parameters:
    ///   - characteristic: The characteristic to read from
    ///   - timeout: Maximum time to wait for a packet
    /// - Returns: Packet data if available, nil if timeout
    func readPacket(for characteristic: CharacteristicUUID, timeout: TimeInterval) async throws -> Data?

    /// Write a packet to the specified characteristic
    /// - Parameters:
    ///   - data: Packet data to write
    ///   - characteristic: The characteristic to write to
    func writePacket(_ data: Data, to characteristic: CharacteristicUUID) async throws

    /// Notify on a characteristic (send without waiting for request)
    /// - Parameters:
    ///   - data: Data to send
    ///   - characteristic: The characteristic to notify on
    func notify(_ data: Data, on characteristic: CharacteristicUUID) async throws

    /// Check if a client is connected
    var isConnected: Bool { get }
}

// MARK: - Message Handler Protocol

/// Protocol for handling specific message types
protocol MessageHandler {
    /// The message type this handler processes
    var messageType: Message.Type { get }

    /// Handle a request message and produce a response
    /// - Parameters:
    ///   - request: The incoming request message
    ///   - state: Current pump state
    ///   - context: Handler context with authentication info
    /// - Returns: Response message to send back
    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message
}

/// Context information passed to message handlers
struct HandlerContext {
    /// Transaction ID from the request
    let txId: UInt8

    /// Characteristic the request was received on
    let characteristic: CharacteristicUUID

    /// Whether the request was properly signed (for signed messages)
    let isAuthenticated: Bool

    /// Derived secret for HMAC signing (if authenticated)
    let derivedSecret: Data?

    /// Time since reset in seconds
    let timeSinceReset: UInt32
}

// MARK: - Pump State Protocol

/// Protocol for accessing and modifying simulated pump state
protocol PumpStateProvider: AnyObject {
    // Device Info
    var serialNumber: String { get }
    var modelNumber: String { get }
    var firmwareVersion: String { get }

    // Insulin Delivery
    var currentBasalRate: Double { get set }
    var activeProfile: String { get set }
    var reservoirLevel: Double { get set }
    var insulinOnBoard: Double { get set }

    // Active Bolus
    var activeBolusAmount: Double? { get set }
    var activeBolusStartTime: Date? { get set }

    // CGM
    var cgmEnabled: Bool { get set }
    var currentGlucose: Int? { get set }
    var glucoseTrend: GlucoseTrend? { get set }

    // Battery & Power
    var batteryPercent: Int { get set }
    var isCharging: Bool { get set }

    // Time
    var pumpStartTime: Date { get }
    var timeSinceReset: UInt32 { get }

    // Settings
    var basalIQEnabled: Bool { get set }
    var controlIQEnabled: Bool { get set }
    var maxBasalRate: Double { get set }
    var maxBolusAmount: Double { get set }

    // Alerts & Alarms
    var activeAlerts: Set<String> { get set }
    var activeReminders: Set<String> { get set }

    // History
    func addHistoryEntry(_ entry: HistoryEntry)
    func getHistoryEntries(count: Int) -> [HistoryEntry]
}

enum GlucoseTrend: Int {
    case rapidlyRising = 1
    case rising = 2
    case stable = 3
    case falling = 4
    case rapidlyFalling = 5
}

struct HistoryEntry {
    let timestamp: Date
    let eventType: String
    let data: [String: Any]
}

// MARK: - Authentication Provider Protocol

/// Protocol for handling authentication
protocol AuthenticationProvider: AnyObject {
    /// Process an authentication message
    /// - Parameters:
    ///   - message: The authentication message
    ///   - context: Handler context
    /// - Returns: Response message
    func processAuthentication(
        message: Message,
        context: HandlerContext
    ) throws -> Message

    /// Get the current derived secret (if authenticated)
    var derivedSecret: Data? { get }

    /// Check if authentication is complete
    var isAuthenticated: Bool { get }
}
