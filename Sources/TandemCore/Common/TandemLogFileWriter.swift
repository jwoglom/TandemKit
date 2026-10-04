import Foundation

/// Serializes every `TandemLogger` file write in the process; separate handles seeking to the same end offset overwrote each other (#502).
final class TandemLogFileWriter {
    static let shared = TandemLogFileWriter(directory: {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("tandem")
    }())

    static let rotationCheckInterval: TimeInterval = 60

    let logFile: URL
    let logFilePrev: URL

    private let directory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var lastRotationCheck: Date?

    init(directory: URL) {
        self.directory = directory
        logFile = directory.appendingPathComponent("tandem_log.txt")
        logFilePrev = directory.appendingPathComponent("tandem_log_prev.txt")
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    func append(_ line: String, now: Date = Date()) {
        let bytes = Array(line.utf8)
        lock.lock()
        defer { lock.unlock() }

        rotateIfDue(now: now)
        guard openIfNeeded() else { return }

        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                close(descriptor)
                descriptor = -1
                return
            }
            offset += written
        }
    }

    private func openIfNeeded() -> Bool {
        if descriptor >= 0, fileManager.fileExists(atPath: logFile.path) { return true }
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(logFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return descriptor >= 0
    }

    private func rotateIfDue(now: Date) {
        if let last = lastRotationCheck, now.timeIntervalSince(last) < Self.rotationCheckInterval { return }
        lastRotationCheck = now

        guard let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
              let created = attributes[.creationDate] as? Date,
              created < Calendar.current.startOfDay(for: now) else { return }

        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        try? fileManager.removeItem(at: logFilePrev)
        try? fileManager.moveItem(at: logFile, to: logFilePrev)
    }
}
