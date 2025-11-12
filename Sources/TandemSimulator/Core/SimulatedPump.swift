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
                await self?.listenOnCharacteristic(characteristic)
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
            // TODO: Send error response if appropriate
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
