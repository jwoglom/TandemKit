import Foundation

enum TandemSourceError: Error, Equatable {
    case notAuthenticated
    case http(status: Int, body: String)
    case transport(String)
    case decoding(String)
}

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
        let data = try await send(url: components.url!, method: "GET", body: nil)
        do {
            return try JSONDecoder().decode(LastEventUploadedResponse.self, from: data)
        } catch {
            throw TandemSourceError.decoding("getlasteventuploaded: \(error)")
        }
    }

    func upload(bodyJSON: Data) async throws {
        _ = try await send(url: baseURL.appendingPathComponent(TandemSourceConfig.uploadPath), method: "POST", body: bodyJSON)
    }

    private func send(url: URL, method: String, body: Data?) async throws -> Data {
        do {
            return try await attempt(url: url, method: method, body: body, forceRefresh: false)
        } catch let TandemSourceError.http(status, _) where status == 401 {
            return try await attempt(url: url, method: method, body: body, forceRefresh: true)
        }
    }

    private func attempt(url: URL, method: String, body: Data?, forceRefresh: Bool) async throws -> Data {
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
            throw TandemSourceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TandemSourceError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw TandemSourceError.http(status: http.statusCode, body: String(data: data.prefix(512), encoding: .utf8) ?? "")
        }
        return data
    }
}
