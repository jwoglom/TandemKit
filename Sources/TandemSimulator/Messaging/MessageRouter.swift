import Foundation
import Logging
import TandemCore

/// Routes incoming messages to appropriate handlers and builds responses
class MessageRouter {
    private let state: PumpStateProvider
    private let authProvider: AuthenticationProvider
    private let assembler = PacketAssembler()
    private let builder = PacketBuilder()
    private let logger = Logger(label: "TandemSimulator.MessageRouter")

    // Message handlers by opCode
    private var handlers: [UInt8: MessageHandler] = [:]

    // Multi-packet assembly state
    private var assemblyState: [CharacteristicUUID: AssemblyState] = [:]
    private let assemblyLock = NSLock()

    struct AssemblyState {
        var packets: [Data] = []
        var expectedOpCode: UInt8?
        var expectedTxId: UInt8?
        var lastPacketTime = Date()
    }

    init(state: PumpStateProvider, authProvider: AuthenticationProvider) {
        self.state = state
        self.authProvider = authProvider

        // Register message handlers
        registerHandlers()
    }

    /// Process an incoming packet and return response packets (if any)
    func processPacket(
        _ packet: Data,
        on characteristic: CharacteristicUUID,
        timeSinceReset: UInt32
    ) async throws -> Data? {
        logger.debug("Processing packet on \(characteristic.prettyName): \(packet.hexadecimalString)")

        // Parse header to determine if this is first packet or continuation
        let header = try assembler.parseHeader(from: packet)

        // Get or create assembly state for this characteristic
        assemblyLock.lock()
        var state = assemblyState[characteristic] ?? AssemblyState()
        assemblyLock.unlock()

        // Add packet to state
        state.packets.append(packet)
        state.lastPacketTime = Date()

        // Check if we have all packets
        let isComplete = header.packetsRemaining == 0
        let expectedPackets = state.packets.count

        if !isComplete {
            // More packets expected, save state and wait
            assemblyLock.lock()
            assemblyState[characteristic] = state
            assemblyLock.unlock()

            logger.debug("Waiting for more packets: have \(expectedPackets), need \(Int(header.packetsRemaining) + 1)")
            return nil
        }

        // We have all packets, assemble the message
        assemblyLock.lock()
        assemblyState[characteristic] = nil // Clear state
        assemblyLock.unlock()

        logger.debug("All packets received, assembling message")

        let assembled = try assembler.assemble(packets: state.packets, characteristic: characteristic)

        // Validate HMAC if message is signed
        if assembled.isSigned {
            if let secret = authProvider.derivedSecret {
                try assembler.validateHMAC(
                    message: assembled,
                    timeSinceReset: timeSinceReset,
                    derivedSecret: secret
                )
            } else {
                logger.warning("Signed message received but no derived secret available")
                // Continue anyway - might be an auth message
            }
        }

        // Create message instance from cargo
        guard let metadata = MessageRegistry.metadata(
            forOpCode: assembled.opCode,
            characteristic: characteristic
        ) else {
            logger.error("Unknown message opCode: \(assembled.opCode) on \(characteristic.prettyName)")
            throw MessageRouterError.unknownOpCode(assembled.opCode)
        }

        let message = metadata.type.init(cargo: assembled.cargo)
        logger.info("Received message: \(metadata.name) (opCode=\(assembled.opCode))")

        // Route to handler and get response
        let response = try await routeMessage(
            message,
            metadata: metadata,
            txId: assembled.txId,
            characteristic: characteristic,
            isAuthenticated: assembled.isSigned,
            timeSinceReset: timeSinceReset
        )

        guard let responseMessage = response else {
            logger.debug("No response for \(metadata.name)")
            return nil
        }

        // Get metadata for response
        guard let responseMetadata = MessageRegistry.metadata(for: responseMessage) else {
            logger.error("No metadata for response message: \(type(of: responseMessage))")
            throw MessageRouterError.noMetadataForResponse
        }

        logger.info("Sending response: \(responseMetadata.name) (opCode=\(responseMetadata.opCode))")

        // Build response packets
        let responsePackets = try builder.build(
            message: responseMessage,
            metadata: responseMetadata,
            txId: assembled.txId,
            timeSinceReset: timeSinceReset,
            derivedSecret: authProvider.derivedSecret,
            characteristic: characteristic
        )

        // Merge packets into single data blob for now
        // (Transport layer will send them appropriately)
        let mergedResponse = responsePackets.reduce(into: Data()) { $0.append($1) }

        return mergedResponse
    }

    // MARK: - Private Methods

    private func routeMessage(
        _ message: Message,
        metadata: MessageMetadata,
        txId: UInt8,
        characteristic: CharacteristicUUID,
        isAuthenticated: Bool,
        timeSinceReset: UInt32
    ) async throws -> Message? {
        let context = HandlerContext(
            txId: txId,
            characteristic: characteristic,
            isAuthenticated: isAuthenticated,
            derivedSecret: authProvider.derivedSecret,
            timeSinceReset: timeSinceReset
        )

        // Check if this is an authentication message
        if metadata.characteristic == .AUTHORIZATION_CHARACTERISTICS {
            logger.debug("Routing to authentication handler")
            return try authProvider.processAuthentication(message: message, context: context)
        }

        // Route to registered handler
        if let handler = handlers[metadata.opCode] {
            logger.debug("Routing to registered handler for opCode \(metadata.opCode)")
            return try handler.handleRequest(message, state: state, context: context)
        }

        logger.warning("No handler registered for opCode \(metadata.opCode) (\(metadata.name))")
        throw MessageRouterError.noHandler(metadata.opCode, metadata.name)
    }

    private func registerHandlers() {
        // Authentication handlers will be registered by authProvider

        // Register status message handlers
        registerHandler(HomeScreenMirrorHandler())
        registerHandler(BasalStatusHandler())
        registerHandler(BolusStatusHandler())
        registerHandler(TimeSinceResetHandler())

        // More handlers will be added as we implement them

        logger.info("Registered \(handlers.count) message handlers")
    }

    private func registerHandler(_ handler: MessageHandler) {
        // Get opCode from message type
        if let metadata = MessageRegistry.metadata(for: handler.messageType) {
            handlers[metadata.opCode] = handler
            logger.debug("Registered handler for \(metadata.name) (opCode=\(metadata.opCode))")
        } else {
            logger.warning("Could not register handler for \(handler.messageType) - no metadata")
        }
    }
}

// MARK: - MessageRegistry Extensions

extension MessageRegistry {
    /// Find metadata by opCode and characteristic
    static func metadata(forOpCode opCode: UInt8, characteristic: CharacteristicUUID) -> MessageMetadata? {
        all.first { meta in
            meta.opCode == opCode && meta.characteristic == characteristic
        }
    }
}

// MARK: - Errors

enum MessageRouterError: Error, LocalizedError {
    case unknownOpCode(UInt8)
    case noMetadataForResponse
    case noHandler(UInt8, String)

    var errorDescription: String? {
        switch self {
        case let .unknownOpCode(opCode):
            return "Unknown message opCode: \(opCode)"
        case .noMetadataForResponse:
            return "No metadata found for response message"
        case let .noHandler(opCode, name):
            return "No handler registered for opCode \(opCode) (\(name))"
        }
    }
}
