import AuthenticationServices
import CryptoKit
import Foundation

/// Runs the Tandem Source interactive login: the OIDC authorization-code + PKCE flow the Mobi app
/// uses, in an `ASWebAuthenticationSession`.
///
/// The flow is brokered. The app does **not** call the OIDC authorize endpoint directly; it opens
/// the Tandem Source SSO web app (`https://sso.tandemdiabetes.com/`) with its own PKCE challenge and
/// a custom-scheme return (`mobi://auth`). That SPA runs the real OIDC against `tdcservices` using
/// its own registered https web callback, forwarding the app's challenge unchanged, then hands the
/// authorization `code` back to `mobi://auth`. The app exchanges the code itself with its verifier —
/// and, because the code is PKCE/redirect-bound to the SPA's web callback, the **token exchange**
/// must send that web callback as `redirect_uri`, not `mobi://auth`. All of this is reproduced from
/// a captured real login.
@MainActor
final class TandemSourceLoginSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Config {
        /// Leg 1 target: the SSO web app, not the OIDC authorize endpoint.
        var authorizeURL = URL(string: "https://sso.tandemdiabetes.com/")!
        var clientId = "0oa65ks2f7rpiHqfa4h7"
        /// What the SSO app redirects back to with the code; the scheme we listen for.
        var returnURI = "mobi://auth"
        var callbackScheme = "mobi"
        /// What the token exchange must present as `redirect_uri` — the code is bound to it.
        var tokenRedirectURI = "https://sso.tandemdiabetes.com/client/authorize/callback"
        var scope = "openid offline_access tandem.devices.assign"
        var countryHint = "US"
    }

    enum LoginError: Error {
        case cancelled
        case noCode
        case badCallback
    }

    private let config: Config
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    init(config: Config = Config(), anchor: ASPresentationAnchor) {
        self.config = config
        self.anchor = anchor
    }

    /// Presents the login and returns the authorization code, the PKCE verifier used, and the
    /// `redirect_uri` the caller must send to the token endpoint (the SSO web callback).
    func authorize() async throws -> (code: String, codeVerifier: String, redirectURI: String) {
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString
        let nonce = UUID().uuidString

        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        // Matches the captured leg-1 request: no response_type (the SSO app adds it when it calls
        // the OIDC endpoint), redirect back to the custom scheme, narrow scope, country hint.
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.returnURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "country_hint", value: config.countryHint),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: config.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: LoginError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? LoginError.badCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                continuation.resume(throwing: LoginError.badCallback)
            }
        }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw LoginError.noCode
        }
        return (code, verifier, config.tokenRedirectURI)
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(CryptoKit.SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
