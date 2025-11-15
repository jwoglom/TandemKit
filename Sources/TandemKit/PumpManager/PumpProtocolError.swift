import Foundation

public enum PumpProtocolError: Error {
    case messageIOException(String)
}

extension PumpProtocolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .messageIOException(str):
            return str
        }
    }
}
