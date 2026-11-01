import Foundation

/// Owns the Tandem Source auth session and throttles uploads for one pump manager.
///
/// The pump manager holds one of these and pokes it after a history sync. It keeps the work off the
/// BLE path, runs at most one upload at a time, and no more often than `minInterval` unless forced
/// (the settings "Upload now" button). All the network and record work lives in the injected
/// `TandemSourceUploader`; this type is just the gate and the token session.
final class TandemSourceController {
    struct Inputs {
        var serial: UInt32
        var deviceInfo: TandemSourceDeviceInfo?
        var deviceAssignmentId: String?
        var store: HistoryLogStore
        var fillGaps: (_ serial: UInt32, _ ranges: [ClosedRange<UInt32>]) async -> Void
        var pumpClock: () -> Date
    }

    let auth: TandemSourceAuthManager
    private let baseURL: URL
    private let minInterval: TimeInterval

    private let lock = NSLock()
    private var inFlight = false
    private var lastAttemptAt: Date?

    init(
        baseURL: URL = TandemSourceConfig.defaultBaseURL,
        minInterval: TimeInterval = .minutes(30),
        auth: TandemSourceAuthManager? = nil
    ) {
        self.baseURL = baseURL
        self.minInterval = minInterval
        self.auth = auth ?? TandemSourceAuthManager(baseURL: baseURL)
    }

    var isAuthenticated: Bool { auth.isAuthenticated }

    /// Kick an upload if one is due. Returns immediately; `completion` runs on an arbitrary thread
    /// only when an upload actually ran. Skips silently when disabled, not signed in, not
    /// configured, already running, or within `minInterval` of the last attempt (unless `force`).
    func trigger(now: Date, force: Bool, inputs: Inputs, completion: @escaping (Result<TandemSourceUploader.Result, Error>) -> Void) {
        // The assignment id is resolved from the account inside the upload task when not already
        // configured, so being signed in is the only precondition here.
        guard auth.isAuthenticated else {
            tandemSourceLogger.debug("Tandem Source upload skipped: not signed in")
            return
        }

        lock.lock()
        if inFlight {
            lock.unlock()
            tandemSourceLogger.debug("Tandem Source upload skipped: one is already running")
            return
        }
        if !force, let last = lastAttemptAt, now.timeIntervalSince(last) < minInterval {
            lock.unlock()
            tandemSourceLogger.debug("Tandem Source upload skipped: last attempt \(Int(now.timeIntervalSince(last))) s ago")
            return
        }
        inFlight = true
        lastAttemptAt = now
        lock.unlock()

        Task {
            let result: Result<TandemSourceUploader.Result, Error>
            do {
                let client = TandemSourceHTTPClient(baseURL: baseURL, tokenProvider: auth)
                let assignmentId: String
                if let configured = inputs.deviceAssignmentId {
                    assignmentId = configured
                } else if let resolved = try await client.fetchDeviceAssignmentId(serial: inputs.serial) {
                    tandemSourceLogger.info("Resolved this pump's Tandem Source device assignment from the account")
                    assignmentId = resolved
                } else {
                    throw TandemSourceUploader.UploadError.notConfigured
                }
                let uploader = makeUploader(inputs, api: client, assignmentId: assignmentId)
                result = .success(try await uploader.uploadPending(serial: inputs.serial))
            } catch {
                result = .failure(error)
            }
            lock.lock()
            inFlight = false
            lock.unlock()
            completion(result)
        }
    }

    private func makeUploader(_ inputs: Inputs, api: TandemSourceAPI, assignmentId: String) -> TandemSourceUploader {
        TandemSourceUploader(deps: TandemSourceUploader.Dependencies(
            api: api,
            store: inputs.store,
            deviceInfo: { inputs.deviceInfo },
            deviceAssignmentId: { assignmentId },
            fillGaps: inputs.fillGaps,
            now: { Date() },
            pumpClock: inputs.pumpClock
        ))
    }
}
