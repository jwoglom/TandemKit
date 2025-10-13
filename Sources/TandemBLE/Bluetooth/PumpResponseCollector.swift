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
    private let requestMetadata: MessageMetadata
    private let expectedResponseMetadata: MessageMetadata?
    private var packetArrayList: PacketArrayList

    public init(wrapper: TronMessageWrapper) {
        self.message = wrapper.message
        self.requestMetadata = wrapper.requestMetadata
        self.expectedResponseMetadata = wrapper.responseMetadata
        self.packetArrayList = wrapper.buildPacketArrayList(.Response)
    }

    /// Get the request message that initiated this collection
    public func getRequest() -> Message {
        message
    }

    /// Get the request metadata
    public func getRequestMetadata() -> MessageMetadata {
        requestMetadata
    }

    /// Get the expected response metadata (if known)
    public func getExpectedResponseMetadata() -> MessageMetadata? {
        expectedResponseMetadata
    }

    @MainActor
    public func ingest(_ data: Data, characteristic: CBUUID) throws -> PumpResponseMessage {
        guard let response = BTResponseParser.parse(message: message,
                                                    packetArrayList: &packetArrayList,
                                                    output: data,
                                                    uuid: characteristic) else {
            throw PumpResponseCollectorError.invalidResponse
        }
        if let message = response.message {
            print("[PumpResponseCollector] message ready: \(message)")
            return response
        }

        print("[PumpResponseCollector] no message yet (dataLen=\(data.count))")

        let needsMore = packetArrayList.needsMorePacket()
        print("[PumpResponseCollector] needsMore=\(needsMore)")
        print("[PumpResponseCollector] firstByteMod15=\(packetArrayList.debugFirstByteMod15)")

        let requestProps = type(of: message).props
        let opCode = packetArrayList.opCode != 0 ? packetArrayList.opCode : packetArrayList.expectedOpCodeValue
        let characteristicUUID = CharacteristicUUID(rawValue: characteristic.uuidString.uppercased()) ?? requestProps.characteristic

        let allData = packetArrayList.buildMessageData()
        let payload = Data(allData.dropFirst(3))
        if let fallback = BTResponseParser.decodeMessage(opCode: opCode,
                                                         characteristic: characteristicUUID.cbUUID,
                                                         payload: payload) {
            print("[PumpResponseCollector] fallback decoded message: \(fallback)")
            return PumpResponseMessage(data: response.data, message: fallback)
        }

        if !needsMore {
            print("[PumpResponseCollector] no more packets expected but decode failed; returning raw")
        }

        return response
    }
}
