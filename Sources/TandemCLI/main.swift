import Foundation
import TandemCore
import TandemBLE
import TandemKit
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

@main
struct TandemCLIMain {
    struct DecodeOptions {
        var characteristic: String?
        var format: OutputFormat = .json
        var packets: [String] = []
    }

    struct EncodeOptions {
        var messageName: String = ""
        var txId: UInt8 = 0
        var authKey: String?
        var timeSinceReset: UInt32?
        var maxChunkSize: Int?
        var format: OutputFormat = .json
        var cargo: String?
        var allowInsulinActions: Bool = false
    }

    struct ListOptions {
        var characteristic: String?
        var type: ListKind?
        var format: OutputFormat = .text
    }

    struct PairOptions {
        var pairingCode: String = ""
        var timeout: TimeInterval = 60.0
    }

    enum ListKind: String {
        case request
        case response

        var messageType: MessageType {
            switch self {
            case .request:
                return .Request
            case .response:
                return .Response
            }
        }
    }

    static var programName: String {
        (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "tandemkit"
    }

    static func main() async {
        do {
            try await runCLI()
            exit(0)
        } catch let error as CLIError {
            if !error.message.isEmpty {
                if error.exitCode == 0 {
                    print(error.message)
                } else {
                    fputs("Error: \(error.message)\n", stderr)
                }
            }
            exit(Int32(error.exitCode))
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private extension TandemCLIMain {
    static func runCLI() async throws {
        let args = CommandLine.arguments
        if args.count < 2 {
            throw CLIError(usage(), exitCode: 0)
        }
        let command = args[1].lowercased()
        let remainder = Array(args.dropFirst(2))
        switch command {
        case "decode":
            let options = try parseDecodeArguments(remainder)
            try runDecode(options: options)
        case "encode":
            let options = try parseEncodeArguments(remainder)
            try await runEncode(options: options)
        case "list":
            let options = try parseListArguments(remainder)
            try runList(options: options)
        case "pair":
            let options = try parsePairArguments(remainder)
            try await runPair(options: options)
        case "help", "-h", "--help":
            print(usage())
        default:
            throw CLIError("Unknown command: \(command)\n\(usage())", exitCode: 1)
        }
    }

    static func parseDecodeArguments(_ args: [String]) throws -> DecodeOptions {
        var options = DecodeOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--characteristic", "-c":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --characteristic.")
                }
                options.characteristic = args[index]
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("Unsupported format: " + args[index] + ". Use json or text.")
                }
                options.format = format
            case "--help", "-h":
                throw CLIError(decodeUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(decodeUsage())")
                }
                options.packets.append(arg)
            }
            index += 1
        }
        if options.packets.isEmpty {
            throw CLIError("Decode expects at least one packet argument.\n\(decodeUsage())")
        }
        return options
    }

    static func parseEncodeArguments(_ args: [String]) throws -> EncodeOptions {
        var options = EncodeOptions()
        var index = 0
        var messageName: String?
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--txid", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --txid.")
                }
                guard let value = UInt16(args[index]), value <= 0xFF else {
                    throw CLIError("--txid expects an integer value between 0 and 255.")
                }
                options.txId = UInt8(value)
            case "--auth-key":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --auth-key.")
                }
                options.authKey = args[index]
            case "--time-since-reset":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --time-since-reset.")
                }
                guard let value = UInt32(args[index]) else {
                    throw CLIError("--time-since-reset expects an unsigned integer value.")
                }
                options.timeSinceReset = value
            case "--max-chunk-size":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --max-chunk-size.")
                }
                guard let value = Int(args[index]), value > 0 else {
                    throw CLIError("--max-chunk-size expects a positive integer.")
                }
                options.maxChunkSize = value
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("--format expects json or text.")
                }
                options.format = format
            case "--cargo":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --cargo.")
                }
                options.cargo = args[index]
            case "--allow-insulin-actions":
                options.allowInsulinActions = true
            case "--help", "-h":
                throw CLIError(encodeUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(encodeUsage())")
                }
                if messageName == nil {
                    messageName = arg
                } else {
                    throw CLIError("Unexpected argument: \(arg)\n\(encodeUsage())")
                }
            }
            index += 1
        }
        guard let name = messageName else {
            throw CLIError("Encode requires a message type name.\n\(encodeUsage())")
        }
        options.messageName = name
        return options
    }

    static func parseListArguments(_ args: [String]) throws -> ListOptions {
        var options = ListOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--characteristic", "-c":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --characteristic.")
                }
                options.characteristic = args[index]
            case "--type", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --type.")
                }
                guard let kind = ListKind(rawValue: args[index].lowercased()) else {
                    throw CLIError("--type expects 'request' or 'response'.")
                }
                options.type = kind
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("--format expects json or text.")
                }
                options.format = format
            case "--help", "-h":
                throw CLIError(listUsage(), exitCode: 0)
            default:
                throw CLIError("Unknown option: \(arg)\n\(listUsage())")
            }
            index += 1
        }
        return options
    }

    static func parsePairArguments(_ args: [String]) throws -> PairOptions {
        var options = PairOptions()
        var index = 0
        var pairingCode: String?
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--timeout", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --timeout.")
                }
                guard let timeout = TimeInterval(args[index]), timeout > 0 else {
                    throw CLIError("--timeout expects a positive number (seconds).")
                }
                options.timeout = timeout
            case "--help", "-h":
                throw CLIError(pairUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(pairUsage())")
                }
                if pairingCode == nil {
                    pairingCode = arg
                } else {
                    throw CLIError("Unexpected argument: \(arg)\n\(pairUsage())")
                }
            }
            index += 1
        }
        guard let code = pairingCode else {
            throw CLIError("Pair requires a pairing code.\n\(pairUsage())")
        }
        options.pairingCode = code
        return options
    }

    static func runDecode(options: DecodeOptions) throws {
        let packetData = try options.packets.map(dataFromHex)
        guard let first = packetData.first else {
            throw CLIError("At least one packet is required to decode a message.")
        }

        let header = try parseHeader(from: first)
        var payload = Data(first.dropFirst(5))
        for extra in packetData.dropFirst() {
            if extra.count < 2 {
                throw CLIError("Additional packets must contain at least 2 bytes (packetsRemaining + txId).")
            }
            payload.append(extra.dropFirst(2))
        }
        if payload.count < 2 {
            throw CLIError("Packet payload is too short to contain CRC bytes.")
        }
        let crc = payload.suffix(2)
        let cargo = Data(payload.dropLast(2))

        let specifiedCharacteristic = try options.characteristic.map { try CharacteristicParser.parse($0) }
        var matches = MessageRegistry.bestMatches(opCode: header.opCode,
                                                  characteristic: specifiedCharacteristic,
                                                  payloadLength: cargo.count)
        if matches.isEmpty {
            matches = MessageRegistry.matches(opCode: header.opCode, characteristic: specifiedCharacteristic)
        }
        if matches.isEmpty {
            let hint = specifiedCharacteristic == nil ? " Provide --characteristic to narrow the search." : ""
            throw CLIError("No message definition matched opcode " + String(header.opCode) + "." + hint)
        }

        let metadata: MessageMetadata
        if matches.count == 1 {
            metadata = matches[0]
        } else {
            if specifiedCharacteristic == nil {
                let options = matches.map { $0.name + " [" + $0.characteristic.rawValue + "]" }.joined(separator: ", ")
                throw CLIError("Multiple messages matched opcode " + String(header.opCode) + ": " + options + ". Provide --characteristic to disambiguate.")
            }
            metadata = matches[0]
        }

        let message = metadata.type.init(cargo: cargo)
        let sanitizedPackets = options.packets.map { sanitizeHexInput($0).lowercased() }
        let output = buildDecodedOutput(metadata: metadata,
                                        message: message,
                                        cargo: cargo,
                                        header: header,
                                        crc: crc,
                                        packets: sanitizedPackets)

        switch options.format {
        case .json:
            try printJSON(output)
        case .text:
            printDecodedText(output: output, message: message)
        }
    }

    @MainActor
    static func runEncode(options: EncodeOptions) throws {
        guard let metadata = MessageRegistry.metadata(forName: options.messageName) else {
            throw CLIError("Unknown message type " + options.messageName + ". Use '" + programName + " list' to view available names.")
        }

        let cargoData: Data
        if let cargo = options.cargo {
            cargoData = try dataFromHex(cargo)
        } else if metadata.size == 0 && !metadata.variableSize {
            cargoData = Data()
        } else {
            throw CLIError("Message " + metadata.name + " expects payload bytes. Provide --cargo <hex>.")
        }

        let message = metadata.type.init(cargo: cargoData)

        if metadata.modifiesInsulinDelivery {
            if !options.allowInsulinActions {
                throw CLIError("Message " + metadata.name + " modifies insulin delivery. Pass --allow-insulin-actions to proceed.")
            }
            PumpStateSupplier.enableActionsAffectingInsulinDelivery()
        }

        var authKeyData: Data?
        if let authKey = options.authKey {
            authKeyData = try dataFromHex(authKey)
        }
        var tsr: UInt32?
        if metadata.signed {
            guard let key = authKeyData else {
                throw CLIError("Message " + metadata.name + " is signed. Provide --auth-key <hex>.")
            }
            guard let time = options.timeSinceReset else {
                throw CLIError("Message " + metadata.name + " is signed. Provide --time-since-reset <seconds>.")
            }
            authKeyData = key
            tsr = time
        }

        do {
            let packets = try Packetize(message: message,
                                        authenticationKey: authKeyData,
                                        txId: options.txId,
                                        timeSinceReset: tsr,
                                        maxChunkSize: options.maxChunkSize)
            let merged = packets.reduce(into: Data()) { $0.append($1.build) }
            let output = buildEncodedOutput(metadata: metadata,
                                             message: message,
                                             cargo: cargoData,
                                             packets: packets,
                                             merged: merged)
            switch options.format {
            case .json:
                try printJSON(output)
            case .text:
                printEncodedText(output: output, message: message)
            }
        } catch is ActionsAffectingInsulinDeliveryNotEnabled {
            throw CLIError("Encoding aborted: actions affecting insulin delivery are disabled. Pass --allow-insulin-actions to override.")
        } catch PacketizeError.missingAuthenticationKey {
            throw CLIError("Authentication key and time since reset are required for signed messages.")
        }
    }

    static func runList(options: ListOptions) throws {
        let specifiedCharacteristic = try options.characteristic.map { try CharacteristicParser.parse($0) }
        var items = MessageRegistry.all
        if let characteristic = specifiedCharacteristic {
            items = items.filter { $0.characteristic == characteristic }
        }
        if let kind = options.type?.messageType {
            items = items.filter { $0.messageType == kind }
        }

        switch options.format {
        case .json:
            let summaries = items.map { metadata -> [String: AnyEncodable] in
                [
                    "name": AnyEncodable(metadata.name),
                    "type": AnyEncodable(String(describing: metadata.messageType)),
                    "characteristic": AnyEncodable(metadata.characteristic.rawValue),
                    "opCode": AnyEncodable(metadata.opCode),
                    "expectedCargoSize": AnyEncodable(metadata.size),
                    "signed": AnyEncodable(metadata.signed),
                    "variableSize": AnyEncodable(metadata.variableSize),
                    "stream": AnyEncodable(metadata.stream),
                    "modifiesInsulinDelivery": AnyEncodable(metadata.modifiesInsulinDelivery)
                ]
            }
            try printJSON(summaries)
        case .text:
            for metadata in items.sorted(by: { $0.name < $1.name }) {
                let kind = String(describing: metadata.messageType)
                let opHex = String(format: "0x%02X", metadata.opCode)
                let line = metadata.name + " [" + kind + "] op: " + String(metadata.opCode) + " (" + opHex + ") characteristic: " + metadata.characteristic.rawValue
                print(line)
            }
        }
    }

    static func usage() -> String {
        return [
            "Usage: " + programName + " <command> [options]",
            "",
            "Commands:",
            "  decode   Decode a message from hex packets.",
            "  encode   Encode a message into BLE packets.",
            "  list     List available message definitions.",
            "  pair     Pair with a Tandem pump via Bluetooth.",
            "",
            "Use '" + programName + " <command> --help' for details on a specific command."
        ].joined(separator: "\n")
    }

    static func decodeUsage() -> String {
        return [
            "Usage: " + programName + " decode [options] <packet> [extra packets...]",
            "",
            "Options:",
            "  -c, --characteristic <value>  Bluetooth characteristic alias or UUID.",
            "  -f, --format <json|text>      Output formatting (default: json)."
        ].joined(separator: "\n")
    }

    static func encodeUsage() -> String {
        return [
            "Usage: " + programName + " encode [options] <MessageName>",
            "",
            "Options:",
            "  -t, --txid <value>            Transaction identifier (0-255). Default: 0.",
            "      --auth-key <hex>          Authentication key for signed messages.",
            "      --time-since-reset <sec>  Pump time since reset for signed messages.",
            "      --max-chunk-size <n>      Override packet chunk size.",
            "  -f, --format <json|text>      Output formatting (default: json).",
            "      --cargo <hex>             Message cargo as hexadecimal.",
            "      --allow-insulin-actions   Permit encoding of insulin-delivery commands."
        ].joined(separator: "\n")
    }

    static func listUsage() -> String {
        return [
            "Usage: " + programName + " list [options]",
            "",
            "Options:",
            "  -c, --characteristic <value>  Filter by characteristic.",
            "  -t, --type <request|response> Filter by message direction.",
            "  -f, --format <json|text>      Output formatting (default: text)."
        ].joined(separator: "\n")
    }

    static func pairUsage() -> String {
        return [
            "Usage: " + programName + " pair [options] <pairing-code>",
            "",
            "Options:",
            "  -t, --timeout <seconds>  Connection timeout (default: 60).",
            "",
            "Pairing Code:",
            "  6-digit code (e.g., 123456) for JPAKE authentication",
            "  16-character code (e.g., abcd-efgh-ijkl-mnop) for legacy authentication"
        ].joined(separator: "\n")
    }

    static func runPair(options: PairOptions) async throws {
        #if canImport(CoreBluetooth) && !os(Linux)
        guard !options.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError("Pairing code cannot be empty.")
        }

        let sanitizedCode = try await MainActor.run {
            try PumpStateSupplier.sanitizeAndStorePairingCode(options.pairingCode)
        }

        let codeLength = sanitizedCode.count
        let pairingMode = codeLength == 6 ? "JPAKE (6-digit)" : "Legacy (16-character)"

        print("Starting Tandem pump pairing")
        print("  Pairing code: \(sanitizedCode)")
        print("  Mode: \(pairingMode)")
        print("  Timeout: \(String(format: "%.0f", options.timeout)) seconds")
        print("")
        print("Searching for nearby Tandem pumps...")

        let coordinator = PairingCoordinator(pairingCode: sanitizedCode, timeout: options.timeout)
        let result: PairingResult

        do {
            result = try await coordinator.start()
        } catch {
            throw CLIError("Pairing failed: \(String(describing: error))")
        }

        let derivedSecretHex = result.pumpState.derivedSecret?.hexadecimalString ?? "<not provided>"
        let serverNonceHex = result.pumpState.serverNonce?.hexadecimalString ?? "<not provided>"
        let authKeyHex = await MainActor.run { PumpStateSupplier.authenticationKey().hexadecimalString }

        print("")
        print("✅ Pairing completed successfully")
        if let name = result.peripheralName {
            print("  Pump name: \(name)")
        }
        if let identifier = result.peripheralIdentifier {
            print("  Peripheral ID: \(identifier.uuidString)")
        }
        print("  Derived secret: \(derivedSecretHex)")
        print("  Server nonce: \(serverNonceHex)")
        print("  Authentication key: \(authKeyHex)")

        print("")
        print("You can persist these values for future sessions using TandemKit or Loop/Trio.")
        #else
        throw CLIError("Pairing command is only available on platforms with CoreBluetooth support.")
        #endif
    }

    static func printDecodedText(output: DecodedMessageOutput, message: Message) {
        let typeDescription = String(describing: output.message.type)
        let headerTx = String(output.header.packetTxId)
        let messageTx = String(output.header.messageTxId)
        let declaredSize = String(output.header.declaredPayloadSize)
        let actualSize = String(output.header.actualPayloadSize)
        print("Message: " + output.message.name + " [" + typeDescription + "]")
        print("Characteristic: " + output.message.characteristicUUID)
        let opcodeHex = String(format: "0x%02X", output.message.opCode)
        print("Opcode: " + String(output.message.opCode) + " (" + opcodeHex + ")")
        print("Packet txId: " + headerTx + "  Message txId: " + messageTx)
        print("Declared payload size: " + declaredSize + " bytes")
        print("Actual payload size: " + actualSize + " bytes")
        print("CRC: " + output.header.crc)
        print("Cargo: " + output.message.cargo)
        let fields = messagePropertyDescriptions(message)
        if !fields.isEmpty {
            print("Fields:")
            for key in fields.keys.sorted() {
                if let value = fields[key] {
                    print("  " + key + ": " + value)
                }
            }
        }
        if !output.packets.isEmpty {
            print("Packets:")
            for (index, hex) in output.packets.enumerated() {
                print("  [" + String(index) + "] " + hex)
            }
        }
    }

    static func printEncodedText(output: EncodedMessageOutput, message: Message) {
        let typeDescription = String(describing: output.message.type)
        print("Message: " + output.message.name + " [" + typeDescription + "]")
        print("Characteristic: " + output.message.characteristicUUID)
        let opcodeHex = String(format: "0x%02X", output.message.opCode)
        print("Opcode: " + String(output.message.opCode) + " (" + opcodeHex + ")")
        print("Cargo: " + output.message.cargo)
        let fields = messagePropertyDescriptions(message)
        if !fields.isEmpty {
            print("Fields:")
            for key in fields.keys.sorted() {
                if let value = fields[key] {
                    print("  " + key + ": " + value)
                }
            }
        }
        print("Packets:")
        for packet in output.packets {
            print("  [" + String(packet.index) + "] remaining=" + String(packet.packetsRemaining) + " txId=" + String(packet.txId) + " hex=" + packet.hex)
        }
        print("Merged: " + output.mergedHex)
    }
}

#if canImport(CoreBluetooth) && !os(Linux)
import CoreBluetooth

private struct PairingResult {
    let pumpState: PumpState
    let peripheralName: String?
    let peripheralIdentifier: UUID?
}

private final class PairingCoordinator: NSObject, BluetoothManagerDelegate, PumpCommDelegate {
    private let pairingCode: String
    private let timeout: TimeInterval
    private let bluetoothManager = BluetoothManager()
    private let pumpComm: PumpComm
    private var transport: PeripheralManagerTransport?

    private var continuation: CheckedContinuation<PairingResult, Error>?
    private let stateQueue = DispatchQueue(label: "com.jwoglom.TandemCLI.PairingCoordinator.state")
    private var timeoutWorkItem: DispatchWorkItem?
    private var lastPumpState: PumpState = PumpState()
    private var targetPeripheral: CBPeripheral?
    private var didStartPairing = false

    init(pairingCode: String, timeout: TimeInterval) {
        self.pairingCode = pairingCode
        self.timeout = timeout
        self.pumpComm = PumpComm(pumpState: nil)
        super.init()

        bluetoothManager.delegate = self
        pumpComm.delegate = self
    }

    deinit {
        bluetoothManager.delegate = nil
        pumpComm.delegate = nil
    }

    func start() async throws -> PairingResult {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync { self.continuation = continuation }
            scheduleTimeout()
            DispatchQueue.main.async {
                self.bluetoothManager.scanForPeripheral()
            }
        }
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: BluetoothManager,
                          shouldConnectPeripheral peripheral: CBPeripheral,
                          advertisementData: [String : Any]?) -> Bool {
        return stateQueue.sync {
            if let target = targetPeripheral, target.identifier != peripheral.identifier {
                return false
            }
            if targetPeripheral == nil {
                targetPeripheral = peripheral
                print("Discovered pump candidate: \(peripheral.name ?? peripheral.identifier.uuidString)")
            }
            return true
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          peripheralManager: PeripheralManager,
                          isReadyWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            print("Connected. Waiting for configuration...")
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        let shouldStartPairing: Bool = stateQueue.sync {
            if didStartPairing {
                return false
            }
            didStartPairing = true
            transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            return true
        }

        guard shouldStartPairing, let transport else { return }

        print("Peripheral configured. Beginning pairing exchange...")

        // Run JPAKE initialization and pairing on background queue to avoid blocking
        Task.detached { [weak self] in
            guard let self else { return }
            do {
#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                if self.pairingCode.count == 6 {
                    print("[PairingCoordinator] priming JPAKE handshake (background)")
                    let builder = JpakeAuthBuilder.initializeWithPairingCode(self.pairingCode)
                    if let initialRequest = builder.nextRequest() {
                    print("[PairingCoordinator] sending initial JPAKE request: \(initialRequest)")
                        do {
                            let initialResponse = try self.pumpComm.sendMessage(transport: transport, message: initialRequest)
                            print("[PairingCoordinator] received initial response: \(initialResponse)")
                            builder.processResponse(initialResponse)
                        } catch {
                            print("[PairingCoordinator] initial JPAKE exchange failed: \(error)")
                            self.finish(.failure(error))
                            return
                        }
                    } else {
                        print("[PairingCoordinator] initial JPAKE request unavailable")
                    }
                }
#endif

                print("[PairingCoordinator] invoking PumpComm.pair")
                try self.pumpComm.pair(transport: transport, pairingCode: self.pairingCode)
                let state = self.stateQueue.sync { self.lastPumpState }
                self.finish(.success(PairingResult(pumpState: state,
                                                   peripheralName: self.targetPeripheral?.name,
                                                   peripheralIdentifier: self.targetPeripheral?.identifier)))
            } catch {
                print("[PairingCoordinator] PumpComm.pair failed: \(error)")
                self.finish(.failure(CLIError(String(describing: error))))
            }
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didIdentifyPump manufacturer: String,
                          model: String) {
        print("[PairingCoordinator] pump model identified manufacturer=\(manufacturer) model=\(model)")
    }

    // MARK: - PumpCommDelegate

    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState) {
        stateQueue.sync {
            self.lastPumpState = pumpState
        }

        let derivedHex = pumpState.derivedSecret?.hexadecimalString ?? "none"
        let nonceHex = pumpState.serverNonce?.hexadecimalString ?? "none"
        print("Pump state updated (derivedSecret: \(derivedHex.prefix(8))…, serverNonce: \(nonceHex.prefix(8))…)")
    }

    // MARK: - Helpers

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.failure(CLIError("Pairing timed out after \(Int(self.timeout)) seconds.")))
        }
        timeoutWorkItem = workItem
        print("[PairingCoordinator] scheduling timeout in \(Int(timeout)) seconds")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.timeout, execute: workItem)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func finish(_ result: Result<PairingResult, Error>) {
        let continuation: CheckedContinuation<PairingResult, Error>? = stateQueue.sync {
            defer { self.continuation = nil }
            return self.continuation
        }

        guard let continuation else { return }

        cancelTimeout()

        DispatchQueue.main.async {
            print("[PairingCoordinator] Disconnecting peripheral")
            self.bluetoothManager.permanentDisconnect()
        }

        switch result {
        case .success(let value):
            print("[PairingCoordinator] Completing with success")
            let derivedHex = value.pumpState.derivedSecret?.hexadecimalString ?? "none"
            let nonceHex = value.pumpState.serverNonce?.hexadecimalString ?? "none"
            print("[PairingCoordinator] PumpState derivedSecret=\(derivedHex) serverNonce=\(nonceHex)")
            continuation.resume(returning: value)
        case .failure(let error):
            print("[PairingCoordinator] Completing with failure: \(error)")
            continuation.resume(throwing: error)
        }
    }
}
#endif
