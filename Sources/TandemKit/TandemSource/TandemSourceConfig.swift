import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Constants for talking to Tandem Source, recovered from the Mobi app and a live capture.
/// The driver presents itself as the Mobi app because the cloud is
/// Tandem's own and only accepts uploads from its known client — this is relaying the user's own
/// pump data to the user's own account, as the pump's app would.
enum TandemSourceConfig {
    /// Live PROD service host. Base URLs are resolved per-country at runtime by the app; this is the
    /// resolved US/PROD value and the default when discovery hasn't run.
    static let defaultBaseURL = URL(string: "https://tdcservices.tandemdiabetes.com")!

    static let getLastEventUploadedPath = "/cloud/upload/getlasteventuploaded"
    static let uploadPath = "/cloud/upload/upload"
    /// `GET …/pumpers/api/pumpers/{pumperId}` returns the account and its assigned devices, each with
    /// its `assignmentId` (the `deviceAssignmentId` uploads need). Used to resolve that id so the
    /// user doesn't have to enter it.
    static let pumpersPath = "/pumpers/api/pumpers"

    /// OIDC (`iss: …/accounts/api`). `authorizationEndpoint`/`tokenEndpoint` are confirmed from the
    /// capture; discovery at `openIDConfigurationPath` can override them per environment.
    static let accountsAuthority = URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api")!
    static let tokenPath = "/accounts/api/connect/token"
    static let authorizePath = "/accounts/api/connect/authorize"
    static let openIDConfigurationPath = "/accounts/api/.well-known/openid-configuration"

    /// The Mobi app's OIDC client id (Okta-style). Reused so the driver's tokens are issued the same
    /// way the app's are.
    static let clientId = "0oa65ks2f7rpiHqfa4h7"

    /// Login is brokered through the Tandem Source SSO web app, which owns the https web callback
    /// registered on the OIDC client. The custom scheme `mobi://auth` is only how that SSO app hands
    /// the code back to the native client (see `TandemSourceLoginSession`). The authorization code is
    /// PKCE/redirect-bound to the web callback, so the token exchange must present it as
    /// `redirect_uri`. All confirmed from a captured real login.
    static let ssoAuthorizeURL = URL(string: "https://sso.tandemdiabetes.com/")!
    static let loginReturnURI = "mobi://auth"
    static let callbackURLScheme = "mobi"
    static let tokenRedirectURI = "https://sso.tandemdiabetes.com/client/authorize/callback"

    /// The country hint the app sends on authorize and on the authorization-code token exchange.
    static let countryHint = "US"

    static let scopes = "openid offline_access tandem.devices.assign"
    static let codeChallengeMethod = "S256"

    /// The `TDCToken` HMAC: `base64(HMAC-SHA1(key, body))`. Key and `HmacSHA1` come from the app's
    /// native `libkeygen.so`; the key is used as raw UTF-8 bytes. Verified byte-for-byte against a
    /// capture.
    static let tdcTokenKey = Data("1hvigLmZyCUBMQxn37SO7Iwn9EoTB1rBUBQg1CFyxcU=".utf8)

    static let appVersion = "3.6.2"
    static let userAgentBuild = "1780692595"

    static var userAgent: String {
        "mobi/\(appVersion) (com.tandemdiabetes.mobi; build:\(userAgentBuild); iOS \(osVersion))"
    }

    static var platform: String {
        #if canImport(UIKit)
            return "\(hardwareModel) [iOS \(osVersion)]"
        #else
            return "iPhone [iOS \(osVersion)]"
        #endif
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "iPhone" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
