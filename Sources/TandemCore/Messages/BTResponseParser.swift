import CoreBluetooth
import Foundation

enum BTResponseParser {
    private static let logger = TandemLogger(category: "BTResponseParser")

    static func parse(
        data: Data,
        characteristic: CBUUID,
        authKey _: Data?,
        response: inout ResponseMessage
    ) {
        // A continuation packet is [packetsRemaining][txId] plus at least one payload byte, and a
        // message whose length is 1 mod 18 ends in exactly that (Packetize chunks the same way).
        let minimumLength = response.fullCargo.isEmpty ? 4 : 3
        guard data.count >= minimumLength else {
            logger.error("Data is too short \(data.count)")
            return
        }

        // TODO: Add cargo size checkers?
        // TODO: Add opCode checkers?
        // TODO: Add txId checkers?

        if response.fullCargo.isEmpty {
            response.needsMorePacket = (Int(data[0] & 0x0F) - 1) >= 0
            response.opCode = data[2]
            response.fullCargo += Data(data.dropFirst(5))

        } else {
            response.needsMorePacket = (Int(data[0] & 0x0F) - 1) >= 0
            response.fullCargo += Data(data.dropFirst(2))
        }

        if !response.needsMorePacket {
            guard let matchingResponseType = MessageRegistry.findResponse(
                opCode: response.opCode,
                characteristic: characteristic
            ) else {
                logger.error("No matching response type - opCode: \(response.opCode)")
                return
            }

            let message = matchingResponseType.self.init(cargo: response.fullCargo)
            response.message = message
        }
    }
}

class ResponseMessage {
    var opCode: UInt8
    var fullCargo: Data
    var needsMorePacket: Bool
    var message: Message?

    init() {
        opCode = 0
        fullCargo = Data()
        needsMorePacket = true
        message = nil
    }
}
