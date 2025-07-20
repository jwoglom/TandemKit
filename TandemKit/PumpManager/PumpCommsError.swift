import Foundation
import LoopKit

public enum PumpCommsError: Error {
    case noPumpPaired
    case noResponse
    case pumpNotConnected
    case commsError(error: Error)
    case unacknowledgedMessage(sequenceNumber: Int, error: Error)
}

extension PumpCommsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPumpPaired:
            return LocalizedString("No pump paired", comment: "Error when no pump is paired")
        case .noResponse:
            return LocalizedString("No response from pump", comment: "Error when no response received")
        case .pumpNotConnected:
            return LocalizedString("Pump not connected", comment: "Error when pump not connected")
        case .commsError(let error):
            return error.localizedDescription
        case .unacknowledgedMessage(_, let error):
            return error.localizedDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noResponse, .pumpNotConnected:
            return LocalizedString("Make sure your pump is nearby", comment: "Recovery when pump not nearby")
        default:
            return nil
        }
    }
}
