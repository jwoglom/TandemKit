import Foundation

public enum PumpChallengeRequestBuilder {
    #if DEBUG
        static var testJpakeHandler: ((Jpake1aResponse, String) throws -> Message)?
    #endif
    public static func processPairingCode(_ pairingCode: String, type: PairingCodeType) throws -> String {
        let processed = type.filterCharacters(pairingCode)
        if type == .long16Char {
            guard processed.count == 16 else { throw InvalidLongPairingCodeFormat() }
        } else if type == .short6Char {
            guard processed.count == 6 else { throw InvalidShortPairingCodeFormat() }
        }
        return processed
    }

    public static func processPairingCode(_ pairingCode: String) throws -> String {
        if pairingCode.count == 6 || PairingCodeType.short6Char.filterCharacters(pairingCode).count == 6 {
            return try processPairingCode(pairingCode, type: .short6Char)
        }
        return try processPairingCode(pairingCode, type: .long16Char)
    }

    public static func create(challengeResponse: Message, pairingCode: String) throws -> Message {
        if let resp = challengeResponse as? CentralChallengeResponse {
            return try createV1(challengeResponse: resp, pairingCode: pairingCode)
        } else if let resp = challengeResponse as? Jpake1aResponse {
            return try createV2(challengeResponse: resp, pairingCode: pairingCode)
        } else {
            throw InvalidPairingCodeFormat("invalid CentralChallengeResponse")
        }
    }

    private static func createV1(challengeResponse: CentralChallengeResponse, pairingCode: String) throws -> Message {
        let appInstanceId = challengeResponse.appInstanceId
        let hmacKey = challengeResponse.hmacKey
        let pairingChars = try processPairingCode(pairingCode, type: .long16Char)
        let challengeHash = HmacSha1(data: Data(pairingChars.utf8), key: hmacKey)
        return PumpChallengeRequest(appInstanceId: Int(appInstanceId), pumpChallengeHash: challengeHash)
    }

    private static func createV2(challengeResponse: Jpake1aResponse, pairingCode: String) throws -> Message {
        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            #if DEBUG
                if let handler = testJpakeHandler {
                    return try handler(challengeResponse, pairingCode)
                }
            #endif
            let sanitizedCode = try processPairingCode(pairingCode, type: .short6Char)
            let builder = JpakeAuthBuilder.initializeWithPairingCode(sanitizedCode)

            guard builder.sentMessages.last is Jpake1aRequest else {
                throw InvalidPairingCodeFormat("JPake session not initialized with client round 1 request")
            }

            builder.processResponse(challengeResponse)

            guard let nextMessage = builder.nextRequest() else {
                throw InvalidPairingCodeFormat("JPake session could not advance after Round 1A response")
            }

            return nextMessage
        #else
            throw InvalidPairingCodeFormat("ECJPAKE not supported on this platform")
        #endif
    }

    public class InvalidPairingCodeFormat: Error, @unchecked Sendable {
        public init(_: String) {}
    }

    public final class InvalidLongPairingCodeFormat: InvalidPairingCodeFormat, @unchecked Sendable {
        public init() { super.init("It should be 16 alphanumeric characters total across 5 groups of 4 characters each.") }
    }

    public final class InvalidShortPairingCodeFormat: InvalidPairingCodeFormat, @unchecked Sendable {
        public init() { super.init("It should be 6 numbers.") }
    }
}
