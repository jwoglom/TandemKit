//
//  PumpFaultCode.swift
//  TandemCore
//
//  Created by ChatGPT on 3/15/25.
//

import Foundation

/// Categories describing how the pump expects callers to react to a fault.
public enum PumpFaultCategory: Equatable {
    /// A temporary transport or pump state issue – callers may retry.
    case transient
    /// A permanent rejection of the request – callers should stop retrying.
    case permanent
    /// Authentication or pairing state is invalid – callers should restart auth.
    case authentication
    /// An unknown classification.
    case unknown
}

/// Enumeration of pump error codes surfaced through ``ErrorResponse``.
public enum PumpFaultCode: Equatable, CustomStringConvertible {
    case undefinedError
    case crcMismatch
    case transactionIdMismatch
    case badCargoLength
    case badOpcode
    case invalidRequiredParameter
    case messageBufferFull
    case invalidAuthenticationError
    case unknown(Int)

    /// Initialize from the raw fault byte sent by the pump.
    public init(rawValue: Int) {
        switch rawValue {
        case 0: self = .undefinedError
        case 1: self = .crcMismatch
        case 3: self = .transactionIdMismatch
        case 4: self = .badCargoLength
        case 6: self = .badOpcode
        case 7: self = .invalidRequiredParameter
        case 8: self = .messageBufferFull
        case 9: self = .invalidAuthenticationError
        default: self = .unknown(rawValue)
        }
    }

    /// Raw value communicated by the pump.
    public var rawValue: Int {
        switch self {
        case .undefinedError: return 0
        case .crcMismatch: return 1
        case .transactionIdMismatch: return 3
        case .badCargoLength: return 4
        case .badOpcode: return 6
        case .invalidRequiredParameter: return 7
        case .messageBufferFull: return 8
        case .invalidAuthenticationError: return 9
        case .unknown(let value): return value
        }
    }

    /// High-level categorization used to drive retry strategy and UI.
    public var category: PumpFaultCategory {
        switch self {
        case .crcMismatch, .transactionIdMismatch, .messageBufferFull:
            return .transient
        case .invalidAuthenticationError:
            return .authentication
        case .badCargoLength, .badOpcode, .invalidRequiredParameter:
            return .permanent
        case .undefinedError, .unknown:
            return .unknown
        }
    }

    /// Returns true when automatic retries are encouraged.
    public var shouldRetry: Bool {
        category == .transient
    }

    /// Localized description suitable for UI surfaces.
    public var localizedDescription: String {
        switch self {
        case .undefinedError:
            return LocalizedString("Undefined pump error", comment: "Pump fault code description for undefined error")
        case .crcMismatch:
            return LocalizedString("Checksum mismatch", comment: "Pump fault code description for CRC mismatch")
        case .transactionIdMismatch:
            return LocalizedString("Transaction identifier mismatch", comment: "Pump fault code description for tx id mismatch")
        case .badCargoLength:
            return LocalizedString("Invalid payload length", comment: "Pump fault code description for bad cargo length")
        case .badOpcode:
            return LocalizedString("Unsupported opcode", comment: "Pump fault code description for bad opcode")
        case .invalidRequiredParameter:
            return LocalizedString("Invalid parameter", comment: "Pump fault code description for invalid parameter")
        case .messageBufferFull:
            return LocalizedString("Pump is busy", comment: "Pump fault code description for message buffer full")
        case .invalidAuthenticationError:
            return LocalizedString("Authentication required", comment: "Pump fault code description for invalid authentication")
        case .unknown(let value):
            return String(format: LocalizedString("Unknown pump error (%d)", comment: "Pump fault code description for unknown code"), value)
        }
    }

    public var description: String { localizedDescription }
}
