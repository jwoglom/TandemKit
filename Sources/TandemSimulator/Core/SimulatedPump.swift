import Foundation
import TandemCore
import TandemBLE
import Logging

/// Main coordinator for the simulated pump
class SimulatedPump {
    private let config: SimulatorConfig
    private let state: SimulatedPumpState
    private let transport: SimulatorTransport
    private let messageRouter: MessageRouter
    private let authProvider: AuthenticationProvider
    private let logger = Logger(label: "TandemSimulator.SimulatedPump")

    private var isRunning = false
    private var listenerTasks: [Task<Void, Never>] = []

    init(config: SimulatorConfig) {
        self.config = config
        self.state = SimulatedPumpState(config: config)

        // Create transport based on config
        if config.useMockTransport {
            self.transport = MockTransport()
        } else {
            // Create BLE peripheral transport
            let deviceName = "\(config.pumpModel.rawValue) \(config.serialNumber)"
            self.transport = BLEPeripheralTransport(deviceName: deviceName)
        }

        // Create authentication provider
        self.authProvider = SimulatorAuthProvider(
            pairingCode: config.pairingCode,
            state: state,
            authMode: config.authenticationMode
        )

        // Create message router
        self.messageRouter = MessageRouter(
            state: state,
            authProvider: authProvider
        )

        logger.info("Simulator initialized", metadata: [
            "serial": .string(config.serialNumber),
            "model": .string(config.pumpModel.rawValue),
            "transport": .string(config.useMockTransport ? "mock" : "BLE")
        ])
    }

    func start() async throws {
        guard !isRunning else {
            logger.warning("Simulator already running")
            return
        }

        isRunning = true
        logger.info("Starting simulator...")

        // Start transport
        try await transport.start()
        logger.info("Transport started")

        // Start listening on all characteristics
        startCharacteristicListeners()

        // Start periodic state updates
        startStateUpdateTimer()

        logger.info("Simulator running and ready for connections")
    }

    func stop() async throws {
        guard isRunning else { return }

        logger.info("Stopping simulator...")
        isRunning = false

        // Cancel all listener tasks
        for task in listenerTasks {
            task.cancel()
        }
        listenerTasks.removeAll()

        // Stop transport
        try await transport.stop()

        logger.info("Simulator stopped")
    }

    // MARK: - Testing Support

    /// Get the mock transport for testing (only available if using mock transport)
    func getMockTransport() -> MockTransport? {
        return transport as? MockTransport
    }

    /// Get the pump state for inspection
    func getPumpState() -> PumpStateProvider {
        return state
    }

    // MARK: - Private Methods

    private func startCharacteristicListeners() {
        let characteristics: [CharacteristicUUID] = [
            .AUTHORIZATION_CHARACTERISTICS,
            .CURRENT_STATUS_CHARACTERISTICS,
            .HISTORY_LOG_CHARACTERISTICS,
            .CONTROL_CHARACTERISTICS
        ]

        for characteristic in characteristics {
            let task = Task { [weak self] in
                guard let self = self else { return }
                await self.listenOnCharacteristic(characteristic)
            }
            listenerTasks.append(task)
        }
    }

    private func listenOnCharacteristic(_ characteristic: CharacteristicUUID) async {
        logger.debug("Started listener for \(characteristic.rawValue)")

        while isRunning && !Task.isCancelled {
            do {
                // Read packet from transport
                guard let packetData = try await transport.readPacket(
                    for: characteristic,
                    timeout: 0.5
                ) else {
                    continue
                }

                logger.debug("Received packet on \(characteristic.rawValue): \(packetData.hexadecimalString)")

                // Process the packet
                await processPacket(packetData, on: characteristic)

            } catch {
                if Task.isCancelled || !isRunning {
                    break
                }
                logger.error("Error reading packet on \(characteristic.rawValue): \(error)")
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        logger.debug("Stopped listener for \(characteristic.rawValue)")
    }

    private func processPacket(_ data: Data, on characteristic: CharacteristicUUID) async {
        do {
            // Simulate processing delay if configured
            if config.simulateRealisticDelays {
                try await Task.sleep(nanoseconds: UInt64(config.responseDelayMs) * 1_000_000)
            }

            // Route the message and get response
            let response = try await messageRouter.processPacket(
                data,
                on: characteristic,
                timeSinceReset: state.timeSinceReset
            )

            // Send response back
            if let responseData = response {
                logger.debug("Sending response on \(characteristic.rawValue): \(responseData.hexadecimalString)")
                try await transport.writePacket(responseData, to: characteristic)
            }

        } catch {
            logger.error("Error processing packet: \(error)")

            // Attempt to send an error response if we can determine how
            await sendErrorResponseIfPossible(for: data, on: characteristic, error: error)
        }
    }

    private func sendErrorResponseIfPossible(
        for data: Data,
        on characteristic: CharacteristicUUID,
        error: Error
    ) async {
        // Try to extract basic packet information to send an error response
        // This is a best-effort approach - if we can't parse enough info, we just log

        guard data.count >= 3 else {
            logger.debug("Packet too short to send error response")
            return
        }

        // Try to extract txId and opCode from the first packet
        // Format: [packetsRemaining] [txId] [opCode] ...
        let txId = data[1]
        let opCode = data[2]

        logger.debug("Attempting error response for opCode \(opCode), txId \(txId)")

        // Look up the request message to find the corresponding response type
        guard let metadata = MessageRegistry.metadata(
            forOpCode: opCode,
            characteristic: characteristic
        ) else {
            logger.debug("Cannot send error response - unknown opCode \(opCode)")
            return
        }

        guard let responseMetadata = MessageRegistry.responseMetadata(for: metadata.type) else {
            logger.debug("Cannot send error response - no response type for \(metadata.name)")
            return
        }

        // Create a minimal error response
        // Most responses that implement StatusMessage have status as first byte
        // For simplicity, we'll create a minimal response with status=1 (generic error)
        let errorCargo = Data([0x01]) // status = 1 (error)

        do {
            // Build error response packet
            let errorMessage = responseMetadata.type.init(cargo: errorCargo)

            // Use message router to build the packet properly
            // Note: This will fail if message requires authentication we don't have
            // In that case, we just log and continue
            logger.info("Sending error response for \(metadata.name) -> \(responseMetadata.name)")

            // For now, we can't easily construct a proper error response without
            // going through the message router, which would require more state.
            // The best we can do is log the error clearly.
            logger.warning("Error response construction requires full message router - error logged only")

        } catch {
            logger.debug("Failed to construct error response: \(error)")
        }
    }

    private func startStateUpdateTimer() {
        let task = Task { [weak self] in
            while self?.isRunning == true && !Task.isCancelled {
                // Update state every second
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard let self = self else { break }

                self.state.updateInsulinOnBoard()
                self.state.updateBattery()
                self.state.updateGlucose()
            }
        }
        listenerTasks.append(task)
    }
}
