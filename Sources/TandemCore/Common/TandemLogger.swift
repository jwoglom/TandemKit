import Foundation
#if canImport(os)
    import os.log
#endif

/// Unified logging system for TandemKit with file persistence.
/// Modeled after DanaKit and MedtrumKit logging implementations.
public final class TandemLogger {
    private let category: String
    private static let subsystem = "com.jwoglom.TandemKit"

    #if canImport(os)
        private let osLog: os.Logger
    #endif

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    private static let fileManager = FileManager.default
    private static let fileQueue = DispatchQueue(label: "com.jwoglom.TandemKit.logger.file")

    public enum Level: Int, CaseIterable, Comparable {
        case trace = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4

        public var description: String {
            switch self {
            case .trace: return "TRACE"
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }

        #if canImport(os)
            var osLogType: OSLogType {
                switch self {
                case .trace: return .debug
                case .debug: return .debug
                case .info: return .info
                case .warning: return .default
                case .error: return .error
                }
            }
        #endif

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public init(category: String) {
        self.category = category
        #if canImport(os)
            osLog = os.Logger(subsystem: TandemLogger.subsystem, category: category)
        #endif
    }

    // MARK: - Public Logging Methods

    /// Trace-level logging. Written to file only, not console.
    public func trace(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.trace, message(), file: file, function: function, line: line)
    }

    /// Debug-level logging. Written to both console and file.
    public func debug(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message(), file: file, function: function, line: line)
    }

    /// Info-level logging. Written to both console and file.
    public func info(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message(), file: file, function: function, line: line)
    }

    /// Warning-level logging. Written to both console and file.
    public func warning(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message(), file: file, function: function, line: line)
    }

    /// Error-level logging. Written to both console and file.
    public func error(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message(), file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(
        _ level: Level,
        _ message: String,
        file: String,
        function: String,
        line: Int
    ) {
        let filename = file.file
        let formattedMessage = "[\(category)] \(message) (\(filename):\(function):\(line))"

        // Write to console (OSLog) - except for trace level
        if level != .trace {
            #if canImport(os)
                osLog.log(level: level.osLogType, "\(formattedMessage, privacy: .public)")
            #else
                print("[\(level.description)] \(formattedMessage)")
            #endif
        }

        // Always write to file
        let timestamp = TandemLogger.dateFormatter.string(from: Date())
        let fileEntry = "[\(timestamp) \(level.description)] \(formattedMessage)\n"
        TandemLogger.writeToFile(fileEntry)
    }

    // MARK: - File Management

    private static func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func getLogDirectory() -> URL {
        getDocumentsDirectory().appendingPathComponent("tandemkit", isDirectory: true)
    }

    private static var logFile: URL {
        getLogDirectory().appendingPathComponent("tandemkit_log.txt")
    }

    private static var prevLogFile: URL {
        getLogDirectory().appendingPathComponent("tandemkit_log_prev.txt")
    }

    private static func writeToFile(_ entry: String) {
        fileQueue.async {
            do {
                let logDir = getLogDirectory()

                // Create directory if needed
                if !fileManager.fileExists(atPath: logDir.path) {
                    try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
                }

                let logFileURL = logFile

                // Check if we need to rotate logs (new day)
                if fileManager.fileExists(atPath: logFileURL.path) {
                    if let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
                       let creationDate = attrs[.creationDate] as? Date,
                       !Calendar.current.isDateInToday(creationDate)
                    {
                        // Rotate: move current to prev
                        let prevURL = prevLogFile
                        if fileManager.fileExists(atPath: prevURL.path) {
                            try? fileManager.removeItem(at: prevURL)
                        }
                        try? fileManager.moveItem(at: logFileURL, to: prevURL)
                    }
                }

                // Create file if needed
                if !fileManager.fileExists(atPath: logFileURL.path) {
                    let header = "TandemKit Log - Created \(dateFormatter.string(from: Date()))\n"
                    try header.data(using: .utf8)?.write(to: logFileURL)
                }

                // Append entry
                if let data = entry.data(using: .utf8) {
                    try data.append(to: logFileURL)
                }
            } catch {
                // Silently fail - don't want logging to crash the app
                #if DEBUG
                    print("TandemLogger file write error: \(error)")
                #endif
            }
        }
    }

    /// Returns URLs for available log files (current and previous).
    public static func getDebugLogs() -> [URL] {
        var logs: [URL] = []
        if fileManager.fileExists(atPath: logFile.path) {
            logs.append(logFile)
        }
        if fileManager.fileExists(atPath: prevLogFile.path) {
            logs.append(prevLogFile)
        }
        return logs
    }

    /// Returns combined content of all log files.
    public static func getDebugLogContent() -> String {
        var content = ""
        for url in getDebugLogs() {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8)
            {
                content += text
                content += "\n--- End of \(url.lastPathComponent) ---\n\n"
            }
        }
        return content
    }

    /// Clears all log files.
    public static func clearLogs() {
        fileQueue.async {
            try? fileManager.removeItem(at: logFile)
            try? fileManager.removeItem(at: prevLogFile)
        }
    }
}

// MARK: - Extensions

private extension Data {
    func append(to url: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: url)
        }
    }
}

private extension String {
    var file: String {
        (self as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
    }
}
