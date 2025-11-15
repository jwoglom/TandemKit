//
//  PumpCommFaultEvent.swift
//  TandemKit
//
//  Created by ChatGPT on 3/15/25.
//

import Foundation
import TandemCore

/// Context describing a pump fault encountered during a request cycle.
public struct PumpCommFaultEvent {
    public let request: Message
    public let response: ErrorResponse
    public let code: PumpFaultCode
    public let attempt: Int
    public let decision: PumpCommRetryDecision

    public init(request: Message,
                response: ErrorResponse,
                code: PumpFaultCode,
                attempt: Int,
                decision: PumpCommRetryDecision) {
        self.request = request
        self.response = response
        self.code = code
        self.attempt = attempt
        self.decision = decision
    }

    public var category: PumpFaultCategory { code.category }
    public var rawCode: Int { code.rawValue }
    public var nextRetryDelay: TimeInterval? { decision.retryDelay }
    public var willRetry: Bool { decision.willRetry }
}
