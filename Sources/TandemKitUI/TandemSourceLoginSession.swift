import AuthenticationServices
import CryptoKit
import Foundation

/// Runs the Tandem Source interactive login: an OIDC authorization-code + PKCE flow in an
/// `ASWebAuthenticationSession`, reusing the Mobi app's client id and custom-scheme redirect. On
/// success it hands the code and PKCE verifier to the pump manager to exchange for tokens.
///
/// The redirect URI is the one auth value not confirmed from the capture; if a first login fails
/// with a redirect error, that is the value to adjust (`TandemSourceLoginConfig`).
@MainActor
final class TandemSourceLoginSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Config {
        var authorizeURL = URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api/connect/authorize")!
        var clientId = "0oa65ks2f7rpiHqfa4h7"
        var redirectURI = "mobi://callback"
        var callbackScheme = "mobi"
        var scope = "openid profile email offline_access phone address tandem.devices.assign"
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

    /// Presents the login and returns the authorization code plus the PKCE verifier used, which the
    /// caller exchanges via `TandemPumpManager.completeTandemSourceSignIn`.
    func authorize() async throws -> (code: String, codeVerifier: String, redirectURI: String) {
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomCodeVerifier()

        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
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
        return (code, verifier, config.redirectURI)
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
