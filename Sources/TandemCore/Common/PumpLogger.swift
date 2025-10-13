import Foundation
#if canImport(Logging)
import Logging
#endif

public enum PumpLogging {
    public typealias Handler = (_ level: PumpLogger.Level, _ label: String, _ message: String) -> Bool

    private static let lock = NSLock()
    private static var handler: Handler?

    @discardableResult
    public static func setHandler(_ newHandler: Handler?) -> Handler? {
        lock.lock()
        let previous = handler
        handler = newHandler
        lock.unlock()
        return previous
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
    public enum Level: CaseIterable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical

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

        #if canImport(Logging)
        var loggerLevel: Logger.Level {
            switch self {
            case .trace: return .trace
            case .debug: return .debug
            case .info: return .info
            case .notice: return .notice
            case .warning: return .warning
            case .error: return .error
            case .critical: return .critical
            }
        }
        #endif
    }

    private let label: String
    #if canImport(Logging)
    private let logger: Logger
    #endif

    public init(label: String) {
        self.label = label
        #if canImport(Logging)
        self.logger = Logger(label: label)
        #endif
    }

    public func log(_ level: Level, _ message: @autoclosure () -> String) {
        let text = message()
        if PumpLogging.handle(level: level, label: label, message: text) {
            return
        }

        #if canImport(Logging)
        logger.log(level: level.loggerLevel, "\(text)")
        #else
        Swift.print("[\(label)] [\(level.description)] \(text)")
        #endif
    }

    public func trace(_ message: @autoclosure () -> String) { log(.trace, message()) }
    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func notice(_ message: @autoclosure () -> String) { log(.notice, message()) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
    public func critical(_ message: @autoclosure () -> String) { log(.critical, message()) }
}
