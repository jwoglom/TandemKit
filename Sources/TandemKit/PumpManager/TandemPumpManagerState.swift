import Foundation
import TandemCore

#if canImport(HealthKit)

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public static let version = 1

    public var pumpState: PumpState?

    public init(pumpState: PumpState?) {
        self.pumpState = pumpState
    }

    public init?(rawValue: RawValue) {
        self.pumpState = nil
    }

    public var rawValue: RawValue {
        return [:]
    }
}
#endif
