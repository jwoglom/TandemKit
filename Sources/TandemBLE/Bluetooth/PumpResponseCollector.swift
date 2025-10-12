import Foundation
import CoreBluetooth
import TandemCore

public enum PumpResponseCollectorError: Error {
    case invalidResponse
}

/// Maintains PacketArrayList state across multiple BLE notifications
/// so callers can stream pump responses until the full message is available.
public final class PumpResponseCollector {
    private let message: Message
    private var packetArrayList: PacketArrayList

    public init(wrapper: TronMessageWrapper) {
        self.message = wrapper.message
        self.packetArrayList = wrapper.buildPacketArrayList(.Response)
    }

    @MainActor
    public func ingest(_ data: Data, characteristic: CBUUID) throws -> PumpResponseMessage {
        guard let response = BTResponseParser.parse(message: message,
                                                    packetArrayList: &packetArrayList,
                                                    output: data,
                                                    uuid: characteristic) else {
            throw PumpResponseCollectorError.invalidResponse
        }
        return response
    }
}
