import Foundation
import CoreBluetooth

/// Parses raw Bluetooth notification packets into pump messages.
/// This is a minimal Swift port of PumpX2 `BTResponseParser` used for unit testing.
struct BTResponseParser {
    static func parse(wrapper: TronMessageWrapper, output: Data, characteristic: CBUUID) -> PumpResponseMessage? {
        var packetArray = wrapper.buildPacketArrayList(.Response)
        return parse(message: wrapper.message, packetArrayList: &packetArray, output: output, uuid: characteristic)
    }

    static func parse(message: Message, packetArrayList: inout PacketArrayList, output: Data, uuid: CBUUID) -> PumpResponseMessage? {
        checkCharacteristicUuid(uuid, output: output)
        packetArrayList.validatePacket(output)
        if packetArrayList.needsMorePacket() {
            return PumpResponseMessage(data: output)
        }

        var authKey = Data()
        if type(of: message).props.signed {
            authKey = PumpStateSupplier.authenticationKey()
        } else {
            authKey = PumpStateSupplier.authenticationKey()
        }

        if packetArrayList.validate(authKey) {
            let allData = packetArrayList.messageData()
            let payload = allData.dropFirst(3)
            // At present TandemKit does not implement message decoding; return raw payload
            return PumpResponseMessage(data: output, message: RawMessage(opCode: packetArrayList.opCode, cargo: Data(payload)))
        } else {
            return PumpResponseMessage(data: output)
        }
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
    static var props = MessageProps(opCode: 0, size: 0, type: .Response, characteristic: .CURRENT_STATUS_CHARACTERISTICS)
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
