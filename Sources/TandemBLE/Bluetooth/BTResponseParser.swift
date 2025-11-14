import Foundation
import CoreBluetooth
import TandemCore

private let responseParserLogger = PumpLogger(label: "TandemBLE.BTResponseParser")

/// Parses raw Bluetooth notification packets into pump messages.
/// This is a minimal Swift port of PumpX2 `BTResponseParser` used for unit testing.
public struct BTResponseParser {
    @MainActor
    public static func parse(wrapper: TronMessageWrapper, output: Data, characteristic: CBUUID) -> PumpResponseMessage? {
        var packetArray = wrapper.buildPacketArrayList(.Response)
        return parse(message: wrapper.message, packetArrayList: &packetArray, output: output, uuid: characteristic)
    }

    @MainActor
    static func parse(message: Message, packetArrayList: inout PacketArrayList, output: Data, uuid: CBUUID) -> PumpResponseMessage? {
        checkCharacteristicUuid(uuid, output: output)
        do {
            try packetArrayList.validatePacket(output)
        } catch {
            return PumpResponseMessage(data: output)
        }
        let needsMore = packetArrayList.needsMorePacket()

        // Enhanced logging with request context
        if let reqMeta = packetArrayList.requestMetadata {
            responseParserLogger.debug("[BTResponseParser] request=\(reqMeta.name) needsMore=\(needsMore) opCode=\(packetArrayList.opCode)")
            if let respMeta = packetArrayList.responseMetadata {
                responseParserLogger.debug("[BTResponseParser]   expecting response=\(respMeta.name) opCode=\(respMeta.opCode)")
            }
        } else {
            responseParserLogger.debug("[BTResponseParser] needsMorePacket=\(needsMore) opCode=\(packetArrayList.opCode)")
        }

        if needsMore {
            return PumpResponseMessage(data: output)
        }

        let allData = packetArrayList.buildMessageData()
        let payload = allData.dropFirst(3)

        var authKey = Data()
        if type(of: message).props.signed {
            authKey = PumpStateSupplier.authenticationKey()
        } else {
            authKey = PumpStateSupplier.authenticationKey()
        }

        let isValid = packetArrayList.validate(authKey)
        if !isValid {
            let reqContext = packetArrayList.requestMetadata?.name ?? "unknown"
            responseParserLogger.warning("[BTResponseParser] Validation failed for request=\(reqContext) opCode=\(packetArrayList.opCode) length=\(payload.count)")
        }

        let decodedMessage = decodeMessage(opCode: packetArrayList.opCode,
                                           characteristic: uuid,
                                           payload: Data(payload))

        if let message = decodedMessage {
            responseParserLogger.debug("[BTResponseParser] decoded \(message)")
            if let reqMeta = packetArrayList.requestMetadata {
                responseParserLogger.debug("[BTResponseParser]   in response to request=\(reqMeta.name)")
            }
            return PumpResponseMessage(data: output, message: message)
        }

        let reqContext = packetArrayList.requestMetadata?.name ?? "unknown"
        responseParserLogger.error("[BTResponseParser] Unable to decode message for request=\(reqContext) opCode=\(packetArrayList.opCode) payloadLength=\(payload.count)")

        return PumpResponseMessage(data: output, message: RawMessage(opCode: packetArrayList.opCode, cargo: Data(payload)))
    }

    public static func decodeMessage(opCode: UInt8, characteristic: CBUUID, payload: Data) -> Message? {
        let charEnum = CharacteristicUUID(rawValue: characteristic.uuidString.uppercased())
        let candidates = MessageRegistry.bestMatches(opCode: opCode,
                                                     characteristic: charEnum,
                                                     payloadLength: payload.count)
        if candidates.isEmpty {
            responseParserLogger.warning("[BTResponseParser] No registry candidate for opCode=\(opCode) characteristic=\(characteristic.uuidString) payloadLength=\(payload.count)")
        }
        guard let meta = candidates.first else { return nil }
        if payload.count != Int(meta.size) {
            responseParserLogger.debug("[BTResponseParser] Candidate \(meta.name) expects size=\(meta.size) but payload=\(payload.count)")
        }
        return meta.type.init(cargo: payload)
    }

    static func parseTxId(_ output: Data) -> UInt8 {
        precondition(output.count >= 3, "BT-returned data should contain at least 3 bytes")
        return output[1]
    }

    static func parseOpcode(_ output: Data) -> UInt8 {
        precondition(output.count >= 3, "BT-returned data should contain at least 3 bytes")
        return output[2]
    }

    private static func checkCharacteristicUuid(_ uuid: CBUUID, output: Data) {
        let allowed = [CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS.cbUUID,
                       CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS.cbUUID,
                       CharacteristicUUID.CONTROL_CHARACTERISTICS.cbUUID]
        if allowed.contains(uuid) {
            return
        } else if uuid == CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS.cbUUID {
            assertionFailure("Qualifying event characteristic: \(output.hexadecimalString)")
        } else if uuid == CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS.cbUUID {
            // history log characteristic not yet implemented
        } else if uuid == CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS.cbUUID {
            // control stream characteristic
        } else {
            assertionFailure("Unsupported UUID: \(uuid) output: \(output.hexadecimalString)")
        }
    }
}

/// Simple container used when decoding of specific message types is unavailable.
private struct RawMessage: Message {
    static let props = MessageProps(opCode: 0, size: 0, type: .Response, characteristic: .CURRENT_STATUS_CHARACTERISTICS)
    var opCode: UInt8
    var cargo: Data

    init(opCode: UInt8, cargo: Data) {
        self.opCode = opCode
        self.cargo = cargo
    }

    init(cargo: Data) {
        self.opCode = 0
        self.cargo = cargo
    }
}
