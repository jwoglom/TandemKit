//
//  PumpCommError.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//


//
//  Basis: OmniBLE/PumpManager/PumpCommsSession.swift
//  Created by Pete Schwamb on 10/13/17.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import TandemCore

public enum PumpCommError: Error, @unchecked Sendable {
    case pumpNotConnected
    case noResponse
    case missingAuthenticationKey
    case errorResponse(response: any Message)
    case notImplemented
    case other
}

extension PumpCommError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .pumpNotConnected:
            return LocalizedString("Pump not connected", comment: "Error message shown when pump expected to be connected but is not")
        case .noResponse:
            return LocalizedString("No response from pump", comment: "Error message shown when no pump response was received")
        case .errorResponse(let response):
            return LocalizedString("Pump Error", comment: "Error response")
        case .notImplemented:
            return LocalizedString("Feature not implemented", comment: "Error message shown when a feature is not yet implemented")
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .pumpNotConnected, .noResponse:
            return LocalizedString("Make sure iPhone is nearby the active pump", comment: "Recovery suggestion when no response is received from pump")
        case .notImplemented:
            return LocalizedString("This feature requires additional pump message implementation", comment: "Recovery suggestion when a feature is not implemented")
        default:
            return nil
        }
    }
}
