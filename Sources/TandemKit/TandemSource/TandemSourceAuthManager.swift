import Foundation
import LoopKit

/// Holds the Tandem Source OIDC tokens and refreshes them.
///
/// The long-lived refresh token is the only durable secret and lives in the keychain, never in
/// `TandemPumpManagerState` (which is serialized to the host app's plist). The access token is kept
/// in memory and re-minted via the `refresh_token` grant — the one auth flow confirmed byte-for-byte
/// from the capture. Interactive first-login (authorization-code + PKCE) happens in the UI layer,
/// which hands the resulting code here for exchange.
final class TandemSourceAuthManager: TandemSourceTokenProvider {
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
    }

    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainManager
    private let keychainService: String

    private let lock = NSLock()
    private var cachedAccessToken: String?
    private var accessTokenExpiry: Date?
    /// A token refreshed within this margin of expiry is treated as already expired.
    private let expiryMargin: TimeInterval = .minutes(5)

    init(
        baseURL: URL = TandemSourceConfig.defaultBaseURL,
        session: URLSession = .shared,
        keychain: KeychainManager = KeychainManager(),
        keychainService: String = "com.tandemdiabetes.tandemkit.tandemSource.refreshToken"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
        self.keychainService = keychainService
    }

    var isAuthenticated: Bool { storedRefreshToken != nil }

    private var storedRefreshToken: String? {
        guard let token = try? keychain.getGenericPasswordForService(keychainService), !token.isEmpty else {
            return nil
        }
        return token
    }

    private func store(refreshToken: String?) {
        try? keychain.replaceGenericPassword(refreshToken, forService: keychainService)
    }

    func signOut() {
        lock.lock(); defer { lock.unlock() }
        cachedAccessToken = nil
        accessTokenExpiry = nil
        store(refreshToken: nil)
    }

    /// Bootstraps from an authorization code obtained by the UI's PKCE login.
    func exchangeAuthorizationCode(_ code: String, codeVerifier: String, redirectURI: String) async throws {
        let response = try await postToken([
            "grant_type": "authorization_code",
            "client_id": TandemSourceConfig.clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectURI,
            "country_hint": TandemSourceConfig.countryHint,
        ])
        guard let refresh = response.refresh_token else {
            throw TandemSourceError.decoding("authorization_code grant returned no refresh_token")
        }
        apply(response, refreshToken: refresh)
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = validCachedToken() {
            return token
        }
        guard let refresh = storedRefreshToken else {
            throw TandemSourceError.notAuthenticated
        }
        let response = try await postToken([
            "grant_type": "refresh_token",
            "client_id": TandemSourceConfig.clientId,
            "refresh_token": refresh,
        ])
        // The server rotates the refresh token on each use; keep the newest so the next refresh works.
        apply(response, refreshToken: response.refresh_token ?? refresh)
        return response.access_token
    }

    private func validCachedToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let token = cachedAccessToken, let expiry = accessTokenExpiry, expiry.timeIntervalSinceNow > expiryMargin else {
            return nil
        }
        return token
    }

    private func apply(_ response: TokenResponse, refreshToken: String) {
        lock.lock()
        cachedAccessToken = response.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600))
        lock.unlock()
        store(refreshToken: refreshToken)
    }

    private func postToken(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(TandemSourceConfig.tokenPath))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(TandemSourceConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(form.map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)

        let data: Data, response: URLResponse
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
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw TandemSourceError.decoding("token: \(error)")
        }
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
