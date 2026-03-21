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
        case .unknown: return "this app"
        }
    }

    /// Name used in place of "DIY": "Trio", "Loop", or fallback "DIY".
    public var diyAlgorithmName: String {
        switch self {
        case .trio: return "Trio"
        case .loop: return "Loop"
        case .unknown: return "DIY"
        }
    }
}
