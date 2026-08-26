import Foundation

#if canImport(OSLog)
import OSLog

/// Driver-facing logger.
///
/// Every line goes to Apple's unified log (`com.jwoglom.TandemKit`) and, at `.info` and above,
/// to each destination registered with ``TandemLogRouter``. By default that is TandemKit's own
/// `Documents/tandem/tandem_log.txt` **and** the host app's general log
/// (`Documents/logs/log.txt`, i.e. the file Trio's `SimpleLogReporter` writes and that Trio's
/// "Share logs" collects), so driver activity shows up in a Trio log bundle without the user
/// having to export the Tandem log separately.
public final class TandemLogger {
    private let category: String
    private let logger: Logger

    public init(category: String) {
        self.category = category
        logger = Logger(subsystem: "com.jwoglom.TandemKit", category: category)
    }

    public func debug(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.debug("\(message, privacy: .public)")
        emit(.debug, msg, file, function, line)
    }

    public func info(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.info("\(message, privacy: .public)")
        emit(.info, msg, file, function, line)
    }

    public func warning(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.warning("\(message, privacy: .public)")
        emit(.warning, msg, file, function, line)
    }

    public func error(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.error("\(message, privacy: .public)")
        emit(.error, msg, file, function, line)
    }

    private func emit(_ level: TandemLogLevel, _ msg: String, _ file: String, _ function: String, _ line: Int) {
        TandemLogRouter.emit(
            category: category,
            level: level,
            message: msg,
            file: file,
            function: function,
            line: line
        )
    }

    /// TandemKit's own log files, for the driver settings "share logs" affordance. The host's
    /// general log is intentionally not included here — the host app shares that one itself.
    func getDebugLogs() -> [URL] {
        TandemFileLogDestination.tandem.existingLogFiles
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}

#else
import Logging

// Desktop/Linux SwiftPM fallback. Apple's OSLog and the app's Documents-based
// file logging are unavailable, so route through swift-log. The public API is
// identical to the OSLog implementation above.
public final class TandemLogger {
    private let category: String
    private let logger: Logger

    public init(category: String) {
        self.category = category
        logger = Logger(label: "com.jwoglom.TandemKit.\(category)")
    }

    public func debug(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.debug("\(file.file) - \(function)#\(line): \(msg)")
        emit(.debug, msg, file, function, line)
    }

    public func info(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.info("\(file.file) - \(function)#\(line): \(msg)")
        emit(.info, msg, file, function, line)
    }

    public func warning(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.warning("\(file.file) - \(function)#\(line): \(msg)")
        emit(.warning, msg, file, function, line)
    }

    public func error(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.error("\(file.file) - \(function)#\(line): \(msg)")
        emit(.error, msg, file, function, line)
    }

    private func emit(_ level: TandemLogLevel, _ msg: String, _ file: String, _ function: String, _ line: Int) {
        TandemLogRouter.emit(
            category: category,
            level: level,
            message: msg,
            file: file,
            function: function,
            line: line
        )
    }

    func getDebugLogs() -> [URL] {
        []
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
#endif
