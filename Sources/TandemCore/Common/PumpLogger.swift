import Foundation
import OSLog

public enum PumpLogging {
    public typealias Handler = (_ level: PumpLogger.Level, _ label: String, _ message: String) -> Bool

    private static let lock = NSLock()
    private static var handler: Handler?

    @discardableResult public static func setHandler(_ newHandler: Handler?) -> Handler? {
        lock.lock()
        let previous = handler
        handler = newHandler
        lock.unlock()
        return previous
    }

    /// Set a minimum log level filter. Logs below this level will be suppressed.
    /// For example, setMinimumLevel(.info) will hide trace and debug logs.
    public static func setMinimumLevel(_ minimumLevel: PumpLogger.Level) {
        setHandler { level, _, _ in
            // Return true to suppress the log
            level < minimumLevel
        }
    }

    static func handle(level: PumpLogger.Level, label: String, message: String) -> Bool {
        lock.lock()
        let current = handler
        lock.unlock()
        guard let handler = current else { return false }
        return handler(level, label, message)
    }
}

public struct PumpLogger {
    public enum Level: Int, CaseIterable, Comparable {
        case trace = 0
        case debug = 1
        case info = 2
        case notice = 3
        case warning = 4
        case error = 5
        case critical = 6

        public var description: String {
            switch self {
            case .trace: return "TRACE"
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .notice: return "NOTICE"
            case .warning: return "WARN"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }

        var loggerLevel: OSLogType {
            switch self {
            case .trace: return .default
            case .debug: return .debug
            case .info: return .info
            case .notice: return .default
            case .warning: return .default
            case .error: return .error
            case .critical: return .error
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let label: String
    private let logger: OSLog

    public init(label: String) {
        self.label = label
        logger = OSLog(category: label)
    }

    public func log(_ level: Level, _ message: @autoclosure () -> String) {
        let text = message()
        if PumpLogging.handle(level: level, label: label, message: text) {
            return
        }

        logger.log(type: level.loggerLevel, "%@", text)
    }

    // Printf-style logging with format string and variadic arguments (OSLog-compatible)
    public func log(_ level: Level, _ format: String, _ args: CVarArg...) {
        let text = String(format: format, arguments: args)
        if PumpLogging.handle(level: level, label: label, message: text) {
            return
        }

        logger.log(type: level.loggerLevel, "%@", text)
    }

    public func trace(_ message: @autoclosure () -> String) { log(.trace, message()) }
    public func trace(_ format: String, _ args: CVarArg...) { log(.trace, format, arguments: args) }

    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func debug(_ format: String, _ args: CVarArg...) { log(.debug, format, arguments: args) }

    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func info(_ format: String, _ args: CVarArg...) { log(.info, format, arguments: args) }

    public func notice(_ message: @autoclosure () -> String) { log(.notice, message()) }
    public func notice(_ format: String, _ args: CVarArg...) { log(.notice, format, arguments: args) }

    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func warning(_ format: String, _ args: CVarArg...) { log(.warning, format, arguments: args) }

    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
    public func error(_ format: String, _ args: CVarArg...) { log(.error, format, arguments: args) }

    public func critical(_ message: @autoclosure () -> String) { log(.critical, message()) }
    public func critical(_ format: String, _ args: CVarArg...) { log(.critical, format, arguments: args) }

    // Helper to convert variadic args to array for String(format:arguments:)
    private func log(_ level: Level, _ format: String, arguments: [CVarArg]) {
        // Strip OSLog-specific privacy annotations like %{public}@ and convert to standard printf format
        let cleanFormat = format
            .replacingOccurrences(of: "%{public}@", with: "%@")
            .replacingOccurrences(of: "%{public}d", with: "%d")
            .replacingOccurrences(of: "%{public}u", with: "%u")
            .replacingOccurrences(of: "%{public}s", with: "%s")
            .replacingOccurrences(of: "%{public}f", with: "%f")
            .replacingOccurrences(of: "%{private}@", with: "%@")
            .replacingOccurrences(of: "%{private}d", with: "%d")
            .replacingOccurrences(of: "%{private}u", with: "%u")
            .replacingOccurrences(of: "%{private}s", with: "%s")
            .replacingOccurrences(of: "%{private}f", with: "%f")

        let text = String(format: cleanFormat, arguments: arguments)
        if PumpLogging.handle(level: level, label: label, message: text) {
            return
        }

        logger.log(type: level.loggerLevel, "%@", text)
    }
}
