import Foundation
import TandemCore

/// Decision returned by a retry policy when handling a pump fault.
public enum PumpCommRetryDecision: Equatable {
    case retry(after: TimeInterval)
    case doNotRetry

    public var retryDelay: TimeInterval? {
        switch self {
        case let .retry(delay): return delay
        case .doNotRetry: return nil
        }
    }

    public var willRetry: Bool {
        if case .retry = self { return true }
        return false
    }
}

/// Strategy object used to determine retry behavior for pump faults.
public protocol PumpCommRetryPolicy {
    func decision(for fault: PumpFaultCode, attempt: Int) -> PumpCommRetryDecision
}

/// Default exponential backoff policy tuned for BLE message retries.
public struct ExponentialPumpCommRetryPolicy: PumpCommRetryPolicy {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let multiplier: Double

    public init(maxAttempts: Int = 3, initialDelay: TimeInterval = 0.5, multiplier: Double = 2.0) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
    }

    public func decision(for fault: PumpFaultCode, attempt: Int) -> PumpCommRetryDecision {
        guard fault.shouldRetry else { return .doNotRetry }
        guard attempt < maxAttempts else { return .doNotRetry }

        let exponent = Double(attempt - 1)
        let delay = initialDelay * pow(multiplier, exponent)
        return .retry(after: delay)
    }
}
