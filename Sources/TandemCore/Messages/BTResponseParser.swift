import CoreBluetooth
import Foundation

enum BTResponseParser {
    private static let logger = TandemLogger(category: "BTResponseParser")

    /// The response `message` is on `characteristic`, or nil when no type has its opcode there or
    /// its cargo is too short for the type.
    static func decode(_ message: AssembledMessage, characteristic: CBUUID) -> Message? {
        guard let matchingResponseType = MessageRegistry.findResponse(opCode: message.opCode, characteristic: characteristic) else {
            logger.error("No matching response type - opCode: \(message.opCode)")
            return nil
        }

        // Message parsers slice their cargo at fixed offsets, which traps rather than throws when
        // the cargo is short.
        let props = matchingResponseType.props
        if !props.variableSize, !props.stream {
            let minimum = matchingResponseType is any JpakeChallengeResponse.Type
                ? Int(props.size) - JpakeCargo.maxScalarShortfall
                : Int(props.size)
            guard message.cargo.count >= minimum else {
                logger.error("Cargo too short for opCode \(message.opCode): \(message.cargo.count) < \(minimum)")
                return nil
            }
        }

        return matchingResponseType.init(cargo: message.cargo)
    }
}
