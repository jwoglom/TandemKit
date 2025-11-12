import Foundation
import TandemCore
import Logging

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(SwiftECC) && canImport(BigInt)
import SwiftECC
import BigInt
#endif

/// Handles authentication (JPAKE and legacy pump challenge)
class SimulatorAuthProvider: AuthenticationProvider {
    private let logger = Logger(label: "TandemSimulator.AuthProvider")

    private let pairingCode: String?
    private let state: PumpStateProvider
    private let authMode: AuthMode

    private var _derivedSecret: Data?
    private var _isAuthenticated = false

    #if canImport(SwiftECC) && canImport(BigInt)
    private var jpakeHandler: JpakeServerHandler?
    #endif

    // Legacy authentication state
    private var legacyHmacKey: Data?
    private var legacyCentralChallenge: Data?

    private let lock = NSLock()

    init(pairingCode: String?, state: PumpStateProvider, authMode: AuthMode) {
        self.pairingCode = pairingCode
        self.state = state
        self.authMode = authMode

        if authMode == .bypass {
            // Bypass mode: auto-authenticate with stub derived secret
            lock.lock()
            _isAuthenticated = true
            // Use a fixed derived secret for testing
            _derivedSecret = Data(repeating: 0x42, count: 20) // 20-byte stub secret
            lock.unlock()
            logger.info("Initialized BYPASS authentication mode (auto-authenticated)")
            return
        }

        #if canImport(SwiftECC) && canImport(BigInt)
        if let code = pairingCode, code.count == 6 {
            // Initialize JPAKE for 6-digit code
            self.jpakeHandler = JpakeServerHandler(pairingCode: code)
            logger.info("Initialized JPAKE authentication with 6-digit code")
        }
        #endif

        if let code = pairingCode, code.count == 16 {
            logger.info("Initialized legacy authentication with 16-character code")
        }
    }

    var derivedSecret: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _derivedSecret
    }

    var isAuthenticated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAuthenticated
    }

    func processAuthentication(
        message: Message,
        context: HandlerContext
    ) throws -> Message {
        logger.info("Processing authentication message: \(type(of: message))")

        // Determine message type and route appropriately
        #if canImport(SwiftECC) && canImport(BigInt)
        switch message {
        case let req as Jpake1aRequest:
            return try handleJpake1a(req, context: context)
        case let req as Jpake1bRequest:
            return try handleJpake1b(req, context: context)
        case let req as Jpake2Request:
            return try handleJpake2(req, context: context)
        case let req as Jpake3SessionKeyRequest:
            return try handleJpake3(req, context: context)
        case let req as Jpake4KeyConfirmationRequest:
            return try handleJpake4(req, context: context)
        default:
            break
        }
        #endif

        // Check for legacy central challenge (first step of legacy auth)
        if message is CentralChallengeRequest {
            return try handleCentralChallenge(message as! CentralChallengeRequest, context: context)
        }

        // Check for legacy pump challenge (second step of legacy auth)
        if message is PumpChallengeRequest {
            return try handlePumpChallenge(message as! PumpChallengeRequest, context: context)
        }

        // Check for challenge request (final step)
        if message is ChallengeRequest {
            return try handleChallenge(message as! ChallengeRequest, context: context)
        }

        logger.error("Unknown authentication message type: \(type(of: message))")
        throw AuthProviderError.unknownAuthMessage
    }

    // MARK: - JPAKE Handlers

    #if canImport(SwiftECC) && canImport(BigInt)
    private func handleJpake1a(_ request: Jpake1aRequest, context: HandlerContext) throws -> Message {
        guard let handler = jpakeHandler else {
            throw AuthProviderError.jpakeNotInitialized
        }

        logger.debug("Handling Jpake1aRequest")

        let response = try handler.processJpake1a(request)

        logger.debug("Sending Jpake1aResponse")
        return response
    }

    private func handleJpake1b(_ request: Jpake1bRequest, context: HandlerContext) throws -> Message {
        guard let handler = jpakeHandler else {
            throw AuthProviderError.jpakeNotInitialized
        }

        logger.debug("Handling Jpake1bRequest")

        let response = try handler.processJpake1b(request)

        logger.debug("Sending Jpake1bResponse")
        return response
    }

    private func handleJpake2(_ request: Jpake2Request, context: HandlerContext) throws -> Message {
        guard let handler = jpakeHandler else {
            throw AuthProviderError.jpakeNotInitialized
        }

        logger.debug("Handling Jpake2Request")

        let response = try handler.processJpake2(request)

        logger.debug("Sending Jpake2Response")
        return response
    }

    private func handleJpake3(_ request: Jpake3SessionKeyRequest, context: HandlerContext) throws -> Message {
        guard let handler = jpakeHandler else {
            throw AuthProviderError.jpakeNotInitialized
        }

        logger.debug("Handling Jpake3SessionKeyRequest")

        let response = try handler.processJpake3(request)

        logger.debug("Sending Jpake3SessionKeyResponse")
        return response
    }

    private func handleJpake4(_ request: Jpake4KeyConfirmationRequest, context: HandlerContext) throws -> Message {
        guard let handler = jpakeHandler else {
            throw AuthProviderError.jpakeNotInitialized
        }

        logger.debug("Handling Jpake4KeyConfirmationRequest")

        let response = try handler.processJpake4(request)

        // After Jpake4, the shared secret should be derived
        if let secret = handler.derivedSecret {
            lock.lock()
            _derivedSecret = secret
            lock.unlock()
            logger.info("JPAKE derived secret established: \(secret.hexadecimalString.prefix(16))...")
        }

        logger.debug("Sending Jpake4KeyConfirmationResponse")
        return response
    }
    #endif

    // MARK: - Legacy Authentication

    private func handleCentralChallenge(_ request: CentralChallengeRequest, context: HandlerContext) throws -> Message {
        guard let code = pairingCode, code.count == 16 else {
            throw AuthProviderError.pumpChallengeNotConfigured
        }

        logger.debug("Handling CentralChallengeRequest (legacy auth step 1)")

        // Store the central challenge for validation
        lock.lock()
        legacyCentralChallenge = request.centralChallenge

        // Generate random 8-byte HMAC key for this session
        legacyHmacKey = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        lock.unlock()

        logger.debug("Generated HMAC key: \(legacyHmacKey!.hexadecimalString)")

        // Generate challenge hash
        // Based on the protocol, this appears to be a hash of the central challenge
        // The exact algorithm may vary, but SHA1 hash of the challenge is a reasonable approach
        let challengeHash = SHA256.hash(request.centralChallenge).prefix(20)

        let response = CentralChallengeResponse(
            appInstanceId: request.appInstanceId,
            centralChallengeHash: Data(challengeHash),
            hmacKey: legacyHmacKey!
        )

        logger.debug("Sending CentralChallengeResponse")
        return response
    }

    private func handlePumpChallenge(_ request: PumpChallengeRequest, context: HandlerContext) throws -> Message {
        guard let code = pairingCode, code.count == 16 else {
            throw AuthProviderError.pumpChallengeNotConfigured
        }

        logger.debug("Handling PumpChallengeRequest (legacy auth step 2)")

        // Get the stored HMAC key from CentralChallengeResponse
        lock.lock()
        let storedHmacKey = legacyHmacKey
        lock.unlock()

        guard let hmacKey = storedHmacKey else {
            logger.error("No HMAC key available - CentralChallengeRequest not received first")
            throw AuthProviderError.invalidState("No HMAC key available")
        }

        // Compute expected HMAC-SHA1 hash of the pairing code
        let expectedHash = HmacSha1(data: Data(code.utf8), key: hmacKey)

        // Compare with received hash
        let success = expectedHash == request.pumpChallengeHash

        if success {
            // Mark as authenticated
            lock.lock()
            _isAuthenticated = true
            lock.unlock()
            logger.info("Legacy pump challenge authentication succeeded")
        } else {
            logger.error("Legacy pump challenge authentication failed")
            logger.error("Expected hash: \(expectedHash.hexadecimalString)")
            logger.error("Received hash: \(request.pumpChallengeHash.hexadecimalString)")
        }

        return PumpChallengeResponse(appInstanceId: request.appInstanceId, success: success)
    }

    // MARK: - Challenge (Final Step)

    private func handleChallenge(_ request: ChallengeRequest, context: HandlerContext) throws -> Message {
        logger.debug("Handling ChallengeRequest (final auth step)")

        // Final challenge step - send pump's nonce and time
        var cargo = Data()

        // Generate server nonce (20 bytes)
        let serverNonce = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        cargo.append(serverNonce)

        // Add time since reset (4 bytes)
        let timeSinceReset = state.timeSinceReset
        cargo.append(contentsOf: withUnsafeBytes(of: timeSinceReset.littleEndian) { Data($0) })

        lock.lock()
        _isAuthenticated = true
        lock.unlock()

        logger.info("Authentication complete - sending ChallengeResponse")

        return ChallengeResponse(cargo: cargo)
    }
}

// MARK: - JPAKE Server Handler

#if canImport(SwiftECC) && canImport(BigInt)
/// Handles server-side JPAKE protocol
class JpakeServerHandler {
    private let pairingCode: String
    private let logger = Logger(label: "TandemSimulator.JpakeServer")

    private var ecJpake: EcJpake
    private var serverRound1: Data?
    private var clientRound1: Data?
    private var serverRound2: Data?
    private var serverNonce3: Data?
    private var _derivedSecret: Data?

    private let appInstanceId: Int = 0
    private let rand: EcJpake.RandomBytesGenerator

    init(pairingCode: String) {
        self.pairingCode = pairingCode
        self.rand = JpakeServerHandler.defaultRandom

        // Initialize EC-JPAKE with server role
        let passwordBytes = JpakeServerHandler.pairingCodeToBytes(pairingCode)
        self.ecJpake = EcJpake(role: .server, password: passwordBytes, random: rand)

        logger.info("JPAKE server initialized with pairing code")
    }

    var derivedSecret: Data? {
        return _derivedSecret
    }

    func processJpake1a(_ request: Jpake1aRequest) throws -> Jpake1aResponse {
        logger.debug("Processing Jpake1a (server receives first half of client round 1)")

        // Store first half of client round 1
        clientRound1 = request.centralChallenge

        // Generate server's round 1 data if not already done
        if serverRound1 == nil {
            serverRound1 = ecJpake.getRound1()
            logger.debug("Generated server round 1: \(serverRound1!.count) bytes")
        }

        // Send first half of server round 1 (165 bytes)
        let serverChallenge1a = serverRound1!.subdata(in: 0..<165)
        let response = Jpake1aResponse(appInstanceId: appInstanceId, centralChallengeHash: serverChallenge1a)

        logger.debug("Sending Jpake1aResponse with first 165 bytes")
        return response
    }

    func processJpake1b(_ request: Jpake1bRequest) throws -> Jpake1bResponse {
        logger.debug("Processing Jpake1b (server receives second half of client round 1)")

        guard let round1a = clientRound1, let serverRound = serverRound1 else {
            throw AuthProviderError.invalidState("Jpake1b received before Jpake1a")
        }

        // Combine both halves of client round 1
        let fullClientRound1 = round1a + request.centralChallenge
        logger.debug("Full client round 1: \(fullClientRound1.count) bytes")

        // Process client's round 1
        ecJpake.readRound1(fullClientRound1)
        logger.debug("Client round 1 processed successfully")

        // Send second half of server round 1 (165 bytes)
        let serverChallenge1b = serverRound.subdata(in: 165..<330)
        let response = Jpake1bResponse(appInstanceId: appInstanceId, centralChallengeHash: serverChallenge1b)

        logger.debug("Sending Jpake1bResponse with second 165 bytes")
        return response
    }

    func processJpake2(_ request: Jpake2Request) throws -> Jpake2Response {
        logger.debug("Processing Jpake2 (server receives client round 2)")

        // Process client's round 2
        let clientRound2 = request.centralChallenge
        ecJpake.readRound2(clientRound2)
        logger.debug("Client round 2 processed successfully")

        // Generate server's round 2
        serverRound2 = ecJpake.getRound2()
        logger.debug("Generated server round 2: \(serverRound2!.count) bytes")

        // Server round 2 is 168 bytes (3-byte curve ID + 165-byte data)
        // Send full 168 bytes
        let response = Jpake2Response(appInstanceId: appInstanceId, centralChallengeHash: serverRound2!)

        logger.debug("Sending Jpake2Response with 168 bytes")
        return response
    }

    func processJpake3(_ request: Jpake3SessionKeyRequest) throws -> Jpake3SessionKeyResponse {
        logger.debug("Processing Jpake3 (server derives shared secret and sends nonce)")

        // Derive the shared secret
        _derivedSecret = ecJpake.deriveSecret()
        logger.info("Derived shared secret: \((_derivedSecret?.hexadecimalString.prefix(16) ?? "nil"))...")

        // Generate server nonce (8 bytes)
        serverNonce3 = generateNonce(8)
        logger.debug("Generated server nonce3: \(serverNonce3!.hexadecimalString)")

        // Send nonce and reserved bytes
        let response = Jpake3SessionKeyResponse(
            appInstanceId: appInstanceId,
            nonce: serverNonce3!,
            reserved: Jpake3SessionKeyResponse.RESERVED
        )

        logger.debug("Sending Jpake3SessionKeyResponse")
        return response
    }

    func processJpake4(_ request: Jpake4KeyConfirmationRequest) throws -> Jpake4KeyConfirmationResponse {
        logger.debug("Processing Jpake4 (server validates client confirmation and sends own)")

        guard let derivedSecret = _derivedSecret, let serverNonce3 = serverNonce3 else {
            throw AuthProviderError.invalidState("Jpake4 received before Jpake3")
        }

        // Validate client's hash digest
        let clientNonce4 = request.nonce
        let clientHashDigest = request.hashDigest

        let expectedClientHash = HmacSha256.hmac(clientNonce4, key: Hkdf.build(nonce: serverNonce3, keyMaterial: derivedSecret))

        guard clientHashDigest == expectedClientHash else {
            logger.error("Client hash digest validation failed")
            logger.error("Expected: \(expectedClientHash.hexadecimalString)")
            logger.error("Received: \(clientHashDigest.hexadecimalString)")
            throw AuthProviderError.authenticationFailed
        }

        logger.debug("Client hash digest validated successfully")

        // Generate server's nonce and hash digest
        let serverNonce4 = generateNonce(8)
        let serverHashDigest = HmacSha256.hmac(serverNonce4, key: Hkdf.build(nonce: serverNonce3, keyMaterial: derivedSecret))

        let response = Jpake4KeyConfirmationResponse(
            appInstanceId: appInstanceId,
            nonce: serverNonce4,
            reserved: Jpake4KeyConfirmationResponse.RESERVED,
            hashDigest: serverHashDigest
        )

        logger.info("JPAKE authentication completed successfully")
        return response
    }

    // MARK: - Helper Methods

    private func generateNonce(_ count: Int) -> Data {
        return rand(count)
    }

    static func pairingCodeToBytes(_ pairingCode: String) -> Data {
        var ret = Data(count: pairingCode.count)
        for (idx, char) in pairingCode.enumerated() {
            ret[idx] = charCode(char)
        }
        return ret
    }

    static func charCode(_ c: Character) -> UInt8 {
        switch c {
        case "0": return 48
        case "1": return 49
        case "2": return 50
        case "3": return 51
        case "4": return 52
        case "5": return 53
        case "6": return 54
        case "7": return 55
        case "8": return 56
        case "9": return 57
        default: return 0xFF
        }
    }

    static func defaultRandom(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        for index in 0..<count {
            data[index] = UInt8.random(in: 0...255)
        }
        return data
    }
}
#endif

// MARK: - Errors

enum AuthProviderError: Error, LocalizedError {
    case unknownAuthMessage
    case jpakeNotInitialized
    case pumpChallengeNotConfigured
    case notImplemented(String)
    case invalidState(String)
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .unknownAuthMessage:
            return "Unknown authentication message type"
        case .jpakeNotInitialized:
            return "JPAKE authentication not initialized"
        case .pumpChallengeNotConfigured:
            return "Pump challenge authentication not configured"
        case .notImplemented(let feature):
            return "Not yet implemented: \(feature)"
        case .invalidState(let details):
            return "Invalid authentication state: \(details)"
        case .authenticationFailed:
            return "Authentication validation failed"
        }
    }
}
