import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum TandemSourceError: Error, Equatable {
    case notAuthenticated
    case http(status: Int, body: String)
    case transport(String)
    case decoding(String)
}

/// What goes into the persisted log, the host's issue report and `lastTandemSourceError`: an HTTP
/// error's body is left out, since a server message can echo back what the request carried.
extension TandemSourceError: CustomStringConvertible {
    var description: String {
        switch self {
        case .notAuthenticated: return "notAuthenticated"
        case let .http(status, _): return "http(status: \(status))"
        case let .transport(reason): return "transport(\(reason))"
        case let .decoding(reason): return "decoding(\(reason))"
        }
    }
}

let tandemSourceLogger = TandemLogger(category: "TandemSource")

/// Supplies a Tandem Source bearer token, refreshing it when asked. The uploader never sees the
/// refresh token; it only ever asks for an access token.
protocol TandemSourceTokenProvider: AnyObject {
    var isAuthenticated: Bool { get }
    /// A valid access token. `forceRefresh` is set after a 401 to discard a token the server
    /// rejected even though it looked unexpired.
    func accessToken(forceRefresh: Bool) async throws -> String
}

/// The two calls the uploader makes against Tandem Source.
protocol TandemSourceAPI {
    func getLastEventUploaded(serial: UInt32, deviceAssignmentId: String) async throws -> LastEventUploadedResponse
    /// POST the already-serialized upload body. The exact bytes passed are what gets signed and sent.
    func upload(bodyJSON: Data) async throws
}

/// URLSession-backed Tandem Source client. Adds the bearer, the `TDCToken` body HMAC, and the Mobi
/// user-agent, and retries once through a forced token refresh on a 401.
final class TandemSourceHTTPClient: TandemSourceAPI {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TandemSourceTokenProvider

    init(baseURL: URL = TandemSourceConfig.defaultBaseURL, session: URLSession = .shared, tokenProvider: TandemSourceTokenProvider) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func getLastEventUploaded(serial: UInt32, deviceAssignmentId: String) async throws -> LastEventUploadedResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent(TandemSourceConfig.getLastEventUploadedPath), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sn", value: String(serial)),
            URLQueryItem(name: "deviceAssignmentId", value: deviceAssignmentId),
        ]
        let data = try await send(url: components.url!, method: "GET", body: nil, endpoint: "getlasteventuploaded")
        do {
            return try JSONDecoder().decode(LastEventUploadedResponse.self, from: data)
        } catch {
            throw TandemSourceError.decoding("getlasteventuploaded: \(error)")
        }
    }

    func upload(bodyJSON: Data) async throws {
        _ = try await send(url: baseURL.appendingPathComponent(TandemSourceConfig.uploadPath), method: "POST", body: bodyJSON, endpoint: "upload")
    }

    /// Resolves the `deviceAssignmentId` for `serial` from the signed-in account, so the user never
    /// has to find and paste a UUID. Reads the `tandem_pumper_id` claim out of the access token,
    /// fetches that pumper, and returns the assignment id of the matching still-assigned device
    /// (preferring one whose `releasedAt` is nil). Returns nil if the account has no such device.
    func fetchDeviceAssignmentId(serial: UInt32) async throws -> String? {
        let token = try await tokenProvider.accessToken(forceRefresh: false)
        guard let pumperId = Self.pumperId(fromJWT: token) else {
            throw TandemSourceError.decoding("access token has no tandem_pumper_id claim")
        }
        let url = baseURL
            .appendingPathComponent(TandemSourceConfig.pumpersPath)
            .appendingPathComponent(pumperId)
        let data = try await send(url: url, method: "GET", body: nil, endpoint: "pumper")
        let pumper: PumperResponse
        do {
            pumper = try JSONDecoder().decode(PumperResponse.self, from: data)
        } catch {
            throw TandemSourceError.decoding("pumper: \(error)")
        }
        let wanted = String(serial)
        let device = pumper.devices.first { $0.serialNumber == wanted && $0.releasedAt == nil }
            ?? pumper.devices.first { $0.serialNumber == wanted }
        if device == nil {
            tandemSourceLogger.warning("No device on the Tandem Source account matches this pump's serial (\(pumper.devices.count) devices on the account)")
        }
        return device?.assignmentId
    }

    /// The `tandem_pumper_id` claim from a JWT, decoded without verifying the signature — the server
    /// issued the token; this only reads our own account id back out of it.
    static func pumperId(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pumperId = claims["tandem_pumper_id"] as? String
        else { return nil }
        return pumperId
    }

    /// `endpoint` names the call in logs in place of the URL, whose path or query carries the
    /// account's pumper id, the serial or the device assignment id.
    private func send(url: URL, method: String, body: Data?, endpoint: String) async throws -> Data {
        do {
            return try await attempt(url: url, method: method, body: body, endpoint: endpoint, forceRefresh: false)
        } catch let TandemSourceError.http(status, _) where status == 401 {
            tandemSourceLogger.warning("Tandem Source \(endpoint) rejected the access token (401); refreshing it and retrying once")
            return try await attempt(url: url, method: method, body: body, endpoint: endpoint, forceRefresh: true)
        }
    }

    private func attempt(url: URL, method: String, body: Data?, endpoint: String, forceRefresh: Bool) async throws -> Data {
        let token = try await tokenProvider.accessToken(forceRefresh: forceRefresh)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TandemSourceConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HmacSha1(data: body, key: TandemSourceConfig.tdcTokenKey).base64EncodedString(), forHTTPHeaderField: "TDCToken")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            tandemSourceLogger.debug("Tandem Source \(endpoint) transport error: \(error.localizedDescription)")
            throw TandemSourceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TandemSourceError.transport("non-HTTP response")
        }
        let bodyPrefix = String(data: data.prefix(512), encoding: .utf8) ?? ""
        guard (200 ..< 300).contains(http.statusCode) else {
            tandemSourceLogger.debug("Tandem Source \(endpoint) answered \(http.statusCode): \(bodyPrefix)")
            throw TandemSourceError.http(status: http.statusCode, body: bodyPrefix)
        }
        tandemSourceLogger.debug("Tandem Source \(endpoint) answered \(http.statusCode), \(data.count) bytes")
        return data
    }
}
