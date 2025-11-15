import Foundation
import TandemCore

public enum PumpCommError: Error {
    case pumpNotConnected
    case noResponse
    case missingAuthenticationKey
    case errorResponse(response: any Message)
    case pumpFault(event: PumpCommFaultEvent)
    case notImplemented
    case other
}

extension PumpCommError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .pumpNotConnected:
            return LocalizedString(
                "Pump not connected",
                comment: "Error message shown when pump expected to be connected but is not"
            )
        case .noResponse:
            return LocalizedString("No response from pump", comment: "Error message shown when no pump response was received")
        case .errorResponse:
            return LocalizedString("Pump Error", comment: "Error response")
        case let .pumpFault(event):
            return String(
                format: LocalizedString("Pump fault: %@", comment: "Error shown when pump returns a fault code"),
                event.code.localizedDescription
            )
        case .notImplemented:
            return LocalizedString(
                "Feature not implemented",
                comment: "Error message shown when a feature is not yet implemented"
            )
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noResponse,
             .pumpNotConnected:
            return LocalizedString(
                "Make sure iPhone is nearby the active pump",
                comment: "Recovery suggestion when no response is received from pump"
            )
        case .notImplemented:
            return LocalizedString(
                "This feature requires additional pump message implementation",
                comment: "Recovery suggestion when a feature is not implemented"
            )
        case let .pumpFault(event):
            switch event.category {
            case .transient:
                return LocalizedString(
                    "The pump reported a temporary fault. TandemKit will retry automatically.",
                    comment: "Recovery suggestion when pump fault is transient"
                )
            case .authentication:
                return LocalizedString(
                    "Authentication with the pump failed. Try reconnecting or re-pairing your pump.",
                    comment: "Recovery suggestion when pump fault is authentication related"
                )
            case .permanent:
                return LocalizedString(
                    "The pump rejected the request. Verify parameters and try again.",
                    comment: "Recovery suggestion when pump fault is permanent"
                )
            case .unknown:
                return LocalizedString(
                    "The pump returned an unknown fault code.",
                    comment: "Recovery suggestion when pump fault is unknown"
                )
            }
        default:
            return nil
        }
    }
}
