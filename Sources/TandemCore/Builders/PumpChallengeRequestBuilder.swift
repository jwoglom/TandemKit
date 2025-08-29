import Foundation

struct PumpChallengeRequestBuilder {
    static func processPairingCode(_ pairingCode: String, type: PairingCodeType) throws -> String {
        let processed = type.filterCharacters(pairingCode)
        if type == .long16Char {
            guard processed.count == 16 else { throw InvalidLongPairingCodeFormat() }
        } else if type == .short6Char {
            guard processed.count == 6 else { throw InvalidShortPairingCodeFormat() }
        }
        return processed
    }

    static func processPairingCode(_ pairingCode: String) throws -> String {
        if pairingCode.count == 6 || PairingCodeType.short6Char.filterCharacters(pairingCode).count == 6 {
            return try processPairingCode(pairingCode, type: .short6Char)
        }
        return try processPairingCode(pairingCode, type: .long16Char)
    }

    static func create(challengeResponse: Message, pairingCode: String) throws -> PumpChallengeRequest {
        if let resp = challengeResponse as? CentralChallengeResponse {
            return try createV1(challengeResponse: resp, pairingCode: pairingCode)
        } else if let resp = challengeResponse as? Jpake1aResponse {
            return try createV2(challengeResponse: resp, pairingCode: pairingCode)
        } else {
            throw InvalidPairingCodeFormat("invalid CentralChallengeResponse")
        }
    }

    private static func createV1(challengeResponse: CentralChallengeResponse, pairingCode: String) throws -> PumpChallengeRequest {
        let appInstanceId = challengeResponse.appInstanceId
        let hmacKey = challengeResponse.hmacKey
        let pairingChars = try processPairingCode(pairingCode, type: .long16Char)
        let challengeHash = HmacSha1(data: Data(pairingChars.utf8), key: hmacKey)
        return PumpChallengeRequest(appInstanceId: Int(appInstanceId), pumpChallengeHash: challengeHash)
    }

    private static func createV2(challengeResponse: Jpake1aResponse, pairingCode: String) throws -> PumpChallengeRequest {
        // TODO: implement ECJPAKE flow
        _ = challengeResponse
        _ = pairingCode
        throw InvalidPairingCodeFormat("ECJPAKE not implemented")
    }

    class InvalidPairingCodeFormat: Error, @unchecked Sendable {
        init(_ reason: String) {}
    }
    final class InvalidLongPairingCodeFormat: InvalidPairingCodeFormat, @unchecked Sendable {
        init() { super.init("It should be 16 alphanumeric characters total across 5 groups of 4 characters each.") }
    }
    final class InvalidShortPairingCodeFormat: InvalidPairingCodeFormat, @unchecked Sendable {
        init() { super.init("It should be 6 numbers.") }
    }
}
