import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Constants for talking to Tandem Source, recovered from the Mobi app and the live capture
/// (`mobi/docs/cloud-upload.md`). The driver presents itself as the Mobi app because the cloud is
/// Tandem's own and only accepts uploads from its known client — this is relaying the user's own
/// pump data to the user's own account, as the pump's app would.
enum TandemSourceConfig {
    /// Live PROD service host. Base URLs are resolved per-country at runtime by the app; this is the
    /// resolved US/PROD value and the default when discovery hasn't run.
    static let defaultBaseURL = URL(string: "https://tdcservices.tandemdiabetes.com")!

    static let getLastEventUploadedPath = "/cloud/upload/getlasteventuploaded"
    static let uploadPath = "/cloud/upload/upload"

    /// OIDC (`iss: …/accounts/api`). `authorizationEndpoint`/`tokenEndpoint` are confirmed from the
    /// capture; discovery at `openIDConfigurationPath` can override them per environment.
    static let accountsAuthority = URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api")!
    static let tokenPath = "/accounts/api/connect/token"
    static let authorizePath = "/accounts/api/connect/authorize"
    static let openIDConfigurationPath = "/accounts/api/.well-known/openid-configuration"

    /// The Mobi app's OIDC client id (Okta-style). Reused so the driver's tokens are issued the same
    /// way the app's are.
    static let clientId = "0oa65ks2f7rpiHqfa4h7"

    /// Registered redirect; a custom scheme the app owns (`CFBundleURLSchemes`/Android manifest).
    /// Not seen in the capture (the app was already logged in), so it is overridable and is the one
    /// value to confirm on a first interactive login.
    static let redirectURI = "mobi://callback"
    static let callbackURLScheme = "mobi"

    static let scopes = "openid profile email offline_access phone address tandem.devices.assign"

    /// The `TDCToken` HMAC: `base64(HMAC-SHA1(key, body))`. Key and `HmacSHA1` come from the app's
    /// native `libkeygen.so`; the key is used as raw UTF-8 bytes. Verified byte-for-byte against the
    /// capture. See `mobi/docs/cloud-upload.md`.
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
