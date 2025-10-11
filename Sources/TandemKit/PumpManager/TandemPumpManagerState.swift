import Foundation
import TandemCore

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public static let version = 1

    public var pumpState: PumpState?

    public init(pumpState: PumpState?) {
        self.pumpState = pumpState
    }

    public init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int, version == TandemPumpManagerState.version else {
            return nil
        }

        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            self.pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            self.pumpState = nil
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": TandemPumpManagerState.version
        ]

        if let pumpState = pumpState {
            raw["pumpState"] = pumpState.rawValue
        }

        return raw
    }
}
