import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Severity of a driver log line.
public enum TandemLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }

    /// Matches the prefix Trio's `Logger` uses, so lines read alike in a shared log.
    public var trioPrefix: String {
        switch self {
        case .debug: return "DEV"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERR"
        }
    }

    public static func < (lhs: TandemLogLevel, rhs: TandemLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A sink for driver log lines. `TandemLogger` fans every line out to all registered
/// destinations.
public protocol TandemLogDestination: AnyObject {
    /// Lines below this level are dropped.
    var minimumLevel: TandemLogLevel { get }

    func write(
        category: String,
        level: TandemLogLevel,
        message: String,
        file: String,
        function: String,
        line: Int,
        date: Date
    )
}

/// Registry + fan-out used by `TandemLogger`. Hosts can replace the defaults at startup to
/// route driver lines through their own logging framework instead.
public enum TandemLogRouter {
    private static let lock = NSRecursiveLock()
    private static var storage: [TandemLogDestination] = defaultDestinations()

    public static var destinations: [TandemLogDestination] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public static func add(_ destination: TandemLogDestination) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(destination)
    }

    public static func removeAllDestinations() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    public static func resetToDefaults() {
        lock.lock()
        defer { lock.unlock() }
        storage = defaultDestinations()
    }

    /// Whether driver lines are mirrored into the host app's general log. On by default; turn
    /// it off on a host whose log writer is not append-atomic.
    public static var isHostGeneralLogEnabled: Bool {
        get {
            #if canImport(Darwin)
            lock.lock()
            defer { lock.unlock() }
            return storage.contains { $0 === TandemFileLogDestination.hostGeneralLog }
            #else
            return false
            #endif
        }
        set {
            #if canImport(Darwin)
            lock.lock()
            defer { lock.unlock() }
            let destination = TandemFileLogDestination.hostGeneralLog
            let present = storage.contains { $0 === destination }
            if newValue, !present {
                storage.append(destination)
            } else if !newValue, present {
                storage.removeAll { $0 === destination }
            }
            #endif
        }
    }

    static func emit(
        category: String,
        level: TandemLogLevel,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        let date = Date()
        // Serialized so two threads never interleave inside a destination.
        lock.lock()
        let targets = storage
        for destination in targets where level >= destination.minimumLevel {
            destination.write(
                category: category,
                level: level,
                message: message,
                file: file,
                function: function,
                line: line,
                date: date
            )
        }
        lock.unlock()
    }

    private static func defaultDestinations() -> [TandemLogDestination] {
        #if canImport(Darwin)
        return [TandemFileLogDestination.tandem, TandemFileLogDestination.hostGeneralLog]
        #else
        // Linux/CLI builds have no Documents directory; swift-log handles output there.
        return []
        #endif
    }
}

#if canImport(Darwin)

/// Appends log lines to a file in the app container's `Documents` directory.
///
/// ``hostGeneralLog`` is the host's own log — the driver runs in-process with Trio, so it is
/// literally the file `SimpleLogReporter` writes and "Share logs" bundles up. Trio rotates it,
/// so we must not. Sharing it also needs both writers to append atomically: ours does, Trio's
/// does after `docs/host-patches/trio-simplelogreporter-atomic-append.patch`, and until that
/// lands either side's lines can be lost. TandemKit's own file is the authoritative record.
public final class TandemFileLogDestination: TandemLogDestination {
    public enum Format {
        /// `[<date> <LEVEL>] File.swift - function#line: message`
        case tandem
        /// `<date> [<Category>] File.swift - function - line - LEVEL: message`, the layout
        /// Trio's `SimpleLogReporter` produces.
        case trio(category: String)
    }

    public let minimumLevel: TandemLogLevel

    private let directory: URL
    private let fileURL: URL
    private let previousFileURL: URL?
    private let format: Format
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public static let tandem = TandemFileLogDestination(
        directoryName: "tandem",
        fileName: "tandem_log.txt",
        previousFileName: "tandem_log_prev.txt",
        format: .tandem,
        minimumLevel: .info
    )

    /// The host app's general log.
    public static let hostGeneralLog = TandemFileLogDestination(
        directoryName: "logs",
        fileName: "log.txt",
        previousFileName: nil,
        format: .trio(category: "TandemKit"),
        minimumLevel: .info
    )

    public init(
        directoryName: String,
        fileName: String,
        previousFileName: String?,
        format: Format,
        minimumLevel: TandemLogLevel
    ) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent(directoryName)
        fileURL = directory.appendingPathComponent(fileName)
        previousFileURL = previousFileName.map { directory.appendingPathComponent($0) }
        self.format = format
        self.minimumLevel = minimumLevel
    }

    public var path: String { fileURL.path }

    /// Existing log files, newest first.
    public var existingLogFiles: [URL] {
        var items: [URL] = []
        if fileManager.fileExists(atPath: fileURL.path) {
            items.append(fileURL)
        }
        if let previousFileURL, fileManager.fileExists(atPath: previousFileURL.path) {
            items.append(previousFileURL)
        }
        return items
    }

    public func write(
        category: String,
        level: TandemLogLevel,
        message: String,
        file: String,
        function: String,
        line: Int,
        date: Date
    ) {
        lock.lock()
        defer { lock.unlock() }

        prepareFile(now: date)

        let entry: String
        switch format {
        case .tandem:
            entry = "[\(Self.dateFormatter.string(from: date)) \(level.label)] "
                + "\(file.lastPathComponentOnly) - \(function)#\(line): \(message)\n"
        case let .trio(hostCategory):
            let categoryLabel = category.isEmpty ? hostCategory : "\(hostCategory).\(category)"
            entry = "\(Self.dateFormatter.string(from: date)) [\(categoryLabel)] "
                + "\(file.lastPathComponentOnly) - \(function) - \(line) - \(level.trioPrefix): \(message)\n"
        }

        appendAtomically(entry)
    }

    private func prepareFile(now: Date) {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let startOfDay = Calendar.current.startOfDay(for: now)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.creationDate: startOfDay])
            return
        }

        // Only files we own get rotated.
        guard let previousFileURL else { return }

        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let creationDate = attributes[.creationDate] as? Date,
           creationDate < startOfDay
        {
            try? fileManager.removeItem(at: previousFileURL)
            try? fileManager.moveItem(at: fileURL, to: previousFileURL)
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.creationDate: startOfDay])
        }
    }

    /// `O_APPEND` + a single `write(2)`: seek-to-end then write is not safe when two writers
    /// share a file.
    private func appendAtomically(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }

        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(descriptor, base.advanced(by: written), buffer.count - written)
                if result <= 0 {
                    if errno == EINTR { continue }
                    break
                }
                written += result
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
}

private extension String {
    var lastPathComponentOnly: String { components(separatedBy: "/").last ?? "" }
}

#endif
