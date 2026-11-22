import Foundation
import LoopKit

#if canImport(OSLog)
import OSLog

public final class TandemLogger {
    private let logger: Logger
    private let fileManager = FileManager.default

    public init(category: String) {
        logger = Logger(subsystem: "com.jwoglom.TandemKit", category: category)
    }

    public func debug(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.info("\(message, privacy: .public)")
        writeToFile(message, .info)
        writeToPumpManager(message, getLevel(.info))
    }

    public func warning(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.warning("\(message, privacy: .public)")
        writeToFile(message, .notice)
        writeToPumpManager(message, getLevel(.notice))
    }

    public func error(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.error("\(message, privacy: .public)")
        writeToFile(message, .error)
        writeToPumpManager(message, getLevel(.error))
    }

    private func writeToFile(_ msg: String, _ type: OSLogEntryLog.Level) {
        TandemLogFileWriter.shared.append("[\(dateFormatter.string(from: Date())) \(getLevel(type))] \(msg)\n")
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    private func getLevel(_ type: OSLogEntryLog.Level) -> String {
        switch type {
        case .info:
            return "INFO"
        case .notice:
            return "WARNING"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        case .debug:
            return "DEBUG"
        default:
            return "UNKNOWN"
        }
    }

    func getDebugLogs() -> [URL] {
        let writer = TandemLogFileWriter.shared
        return [writer.logFile, writer.logFilePrev].filter { fileManager.fileExists(atPath: $0.path) }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}

#else
import Logging

// Desktop/Linux SwiftPM fallback. Apple's OSLog and the app's Documents-based
// file logging are unavailable, so route through swift-log. The public API and
// the host's device log are as in the OSLog implementation above.
public final class TandemLogger {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(label: "com.jwoglom.TandemKit.\(category)")
    }

    public func debug(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.debug("\(file.file) - \(function)#\(line): \(msg)")
    }

    public func info(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.info("\(message)")
        writeToPumpManager(message, "INFO")
    }

    public func warning(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.warning("\(message)")
        writeToPumpManager(message, "WARNING")
    }

    public func error(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.error("\(message)")
        writeToPumpManager(message, "ERROR")
    }

    func getDebugLogs() -> [URL] {
        []
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
#endif

/// Info, warning and error lines also go to the host's device log, which Loop and Trio keep per pump manager.
extension TandemLogger {
    private static let pumpManagerLock = NSLock()
    private weak static var adoptedPumpManager: TandemPumpManager?

    /// The manager a host adopted last; a host runs one at a time.
    static var pumpManager: TandemPumpManager? {
        get {
            pumpManagerLock.lock()
            defer { pumpManagerLock.unlock() }
            return adoptedPumpManager
        }
        set {
            pumpManagerLock.lock()
            defer { pumpManagerLock.unlock() }
            adoptedPumpManager = newValue
        }
    }

    func writeToPumpManager(_ msg: String, _ level: String) {
        guard let pumpManager = Self.pumpManager, pumpManager.canNotifyDelegate else { return }
        let identifier = pumpManager.logDeviceIdentifier

        pumpManager.pumpManagerDelegate?.deviceManager(
            pumpManager,
            logEventForDeviceIdentifier: identifier,
            type: .delegate,
            message: "[\(level)] \(msg)",
            completion: nil
        )
    }
}
