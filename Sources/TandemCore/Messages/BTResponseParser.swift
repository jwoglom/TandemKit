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
        guard data.count > 3 else {
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

            // Message parsers slice their cargo at fixed offsets, which traps rather than throws
            // when the cargo is short. Assembled cargo carries the packet's 2-byte CRC on the end,
            // so a well-formed message clears its declared size; anything below the minimum is a
            // truncated or corrupt notification and is dropped.
            let props = matchingResponseType.props
            if !props.variableSize, !props.stream {
                let minimum = matchingResponseType is any JpakeChallengeResponse.Type
                    ? Int(props.size) - JpakeCargo.maxScalarShortfall
                    : Int(props.size)
                guard response.fullCargo.count >= minimum else {
                    logger.error(
                        "Cargo too short for opCode \(response.opCode): \(response.fullCargo.count) < \(minimum)"
                    )
                    return
                }
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
