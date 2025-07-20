import Foundation

/// Container for data received from the pump over BLE.
/// Mirrors PumpX2 `PumpResponseMessage` but simplified.
struct PumpResponseMessage {
    let data: Data
    let message: Message?

    init(data: Data) {
        self.data = data
        self.message = nil
    }

    init(data: Data, message: Message) {
        self.data = data
        self.message = message
    }
}