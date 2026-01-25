import Foundation
import TandemCore

/// Container for data received from the pump over BLE.
/// Mirrors PumpX2 `PumpResponseMessage` but simplified.
public struct PumpResponseMessage {
    public let data: Data
    public let message: Message?

    public init(data: Data) {
        self.data = data
        message = nil
    }

    public init(data: Data, message: Message) {
        self.data = data
        self.message = message
    }
}
