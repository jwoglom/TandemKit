import Foundation
import TandemCore

public enum PumpCommError: Error {
    case pumpNotConnected
    case noResponse
    case missingAuthenticationKey
    case errorResponse(context: String? = nil, request: (any Message)? = nil, response: (any Message)? = nil)
    case pumpFault(event: PumpCommFaultEvent)
    case notImplemented
    case pumpChallengeError
    case invalidPacket
    case jpakeUnavailable
    case requestConstructionFailed(reason: String)
    case unexpectedResponse(expected: String, actual: String)
    case invalidPumpChallengeResponse
    case initialStateMessagesFailed
    case pumpModelUnsupported(modelNum: UInt32)
    case noActiveBolus
    case responseParsingFailed(underlying: Error)
    case transportError(underlying: Error)
    case invalidScheduledBasalRate
    case other
}

extension PumpCommError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .pumpNotConnected:
            return String(
                localized: "Pump not connected",
                comment: "Error message shown when pump expected to be connected but is not"
            )
        case .noResponse:
            return String(localized: "No response from pump", comment: "Error message shown when no pump response was received")
        case let .errorResponse(context, request, response):
            if let context = context {
                return String(
                    format: String(
                        localized: "Pump Error: %@",
                        comment: "Error message shown when pump returns an error for a command"
                    ),
                    context
                )
            } else if let request = request {
                return String(
                    format: String(
                        localized: "Pump Error: Error sending %@",
                        comment: "Error message shown when pump returns an error for a command"
                    ),
                    String("\(type(of: request))")
                )
            } else if let response = response {
                return String(
                    format: String(
                        localized: "Pump Error: Error sending %@",
                        comment: "Error message shown when pump returns an error for a command"
                    ),
                    String("\(type(of: response))")
                )
            } else {
                return String(
                    localized: "Pump Error: unknown",
                    comment: "Error message shown when pump returns an error for a command"
                )
            }
        case let .pumpFault(event):
            return String(
                format: String(localized: "Pump fault: %@", comment: "Error shown when pump returns a fault code"),
                event.code.localizedDescription
            )
        case .notImplemented:
            return String(
                localized: "Feature not implemented",
                comment: "Error message shown when a feature is not yet implemented"
            )
        case .pumpChallengeError:
            return String(
                localized: "Pump challenge error",
                comment: "Error shown when we cannot perform crypto challenge operations to pair"
            )
        case .jpakeUnavailable:
            return String(
                localized: "Secure pairing unavailable",
                comment: "Error shown when the JPake pairing flow is not available"
            )
        case let .requestConstructionFailed(reason):
            return String(
                format: String(localized: "Failed to build pump request: %@", comment: "Pump request build failure"),
                reason
            )
        case let .unexpectedResponse(expected, actual):
            return String(
                format: String(
                    localized: "Unexpected pump response (expected %@, received %@)",
                    comment: "Unexpected pump response type"
                ),
                expected,
                actual
            )
        case .invalidPumpChallengeResponse:
            return String(
                localized: "Pump challenge response invalid",
                comment: "Error when pump challenge response contents were not valid"
            )
        case .initialStateMessagesFailed:
            return String(
                localized: "Initial state messages failed, please retry pairing",
                comment: "Error shown when initial pump requests after auth fail"
            )
        case let .pumpModelUnsupported(modelNum):
            return String(
                format: String(
                    localized: "Tandem pump model unknown or unsupported (received %@)",
                    comment: "Error shown when pump model is not known"
                ),
                modelNum
            )
        case .noActiveBolus:
            return String(
                localized: "No active bolus to cancel",
                comment: "Error when cancel bolus requested without an active bolus"
            )
        case let .responseParsingFailed(underlying):
            return String(
                format: String(
                    localized: "Failed to parse pump response: %@",
                    comment: "Error when parser fails"
                ),
                String(describing: underlying)
            )
        case let .transportError(underlying):
            return String(
                format: String(
                    localized: "Transport error: %@",
                    comment: "Error when BLE transport fails"
                ),
                String(describing: underlying)
            )
        case .invalidScheduledBasalRate:
            return String(
                localized: "Invalid scheduled basal rate",
                comment: "Error when scheduled basal rate is invalid"
            )
        default:
            return "Other PumpCommError: \(String(describing: self))"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noResponse,
             .pumpNotConnected:
            return String(
                localized: "Make sure iPhone is nearby the active pump",
                comment: "Recovery suggestion when no response is received from pump"
            )
        case .notImplemented:
            return String(
                localized: "This feature requires additional pump message implementation",
                comment: "Recovery suggestion when a feature is not implemented"
            )
        case .jpakeUnavailable:
            return String(
                localized: "This build was unable to initialize the cryptography components. Please reinstall the application.",
                comment: "Recovery suggestion when JPake is unavailable"
            )
        case .requestConstructionFailed:
            return String(
                localized: "Please try again. If the problem persists, re-pair your pump.",
                comment: "Recovery suggestion when building a request failed"
            )
        case .initialStateMessagesFailed,
             .invalidPumpChallengeResponse,
             .responseParsingFailed,
             .transportError,
             .unexpectedResponse:
            return String(
                localized: "Please retry pairing and check your pairing code.",
                comment: "Recovery suggestion for transport/response failures"
            )
        case .noActiveBolus:
            return String(
                localized: "No bolus is running.",
                comment: "Recovery suggestion when cancel bolus is called without an active bolus"
            )
        case let .pumpFault(event):
            switch event.category {
            case .transient:
                return String(
                    localized: "The pump reported a temporary fault. TandemKit will retry automatically.",
                    comment: "Recovery suggestion when pump fault is transient"
                )
            case .authentication:
                return String(
                    localized: "Authentication with the pump failed. Try reconnecting or re-pairing your pump.",
                    comment: "Recovery suggestion when pump fault is authentication related"
                )
            case .permanent:
                return String(
                    localized: "The pump rejected the request. Verify parameters and try again.",
                    comment: "Recovery suggestion when pump fault is permanent"
                )
            case .unknown:
                return String(
                    localized: "The pump returned an unknown fault code.",
                    comment: "Recovery suggestion when pump fault is unknown"
                )
            }

        case .invalidScheduledBasalRate:
            return String(
                localized: "Temp basal cannot be performed while scheduled basal rate is 0 or no basal profile exists",
                comment: "Recovery suggestion when scheduled basal rate is invalid"
            )
        default:
            return nil
        }
    }
}
