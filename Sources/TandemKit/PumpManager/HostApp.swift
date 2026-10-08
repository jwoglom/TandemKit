import Foundation

public enum HostApp {
    case trio
    case loop
    case unknown

    public static let current: HostApp = {
        guard let bundleId = Bundle.main.bundleIdentifier?.lowercased() else {
            return .unknown
        }
        if bundleId.hasSuffix(".trio") {
            return .trio
        }
        if bundleId.hasSuffix(".loopkit") {
            return .loop
        }
        return .unknown
    }()

    /// Human-readable app name: "Trio", "Loop", or "this app" as fallback.
    public var appName: String {
        switch self {
        case .trio: return "Trio"
        case .loop: return "Loop"
        case .unknown:
            return String(
                localized: "this app",
                comment: "Stands in for the host app's name in a sentence when the app is neither Trio nor Loop"
            )
        }
    }

    /// Names the app's settings in a sentence ("your current Trio configuration"): "Trio", "Loop",
    /// or "app" as fallback, where `appName`'s "this app" would not read.
    public var settingsName: String {
        switch self {
        case .trio: return "Trio"
        case .loop: return "Loop"
        case .unknown:
            return String(
                localized: "app",
                comment: "Stands in for the host app's name before a noun (\"your app configuration\") when the app is neither Trio nor Loop"
            )
        }
    }

    /// Name used in place of "DIY": "Trio", "Loop", or fallback "DIY".
    public var diyAlgorithmName: String {
        switch self {
        case .trio: return "Trio"
        case .loop: return "Loop"
        case .unknown:
            return String(
                localized: "DIY",
                comment: "Name of the host app's dosing algorithm when the app is neither Trio nor Loop"
            )
        }
    }
}
