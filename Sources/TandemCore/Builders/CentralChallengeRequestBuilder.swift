import Foundation

struct CentralChallengeRequestBuilder {
    static func create(appInstanceId: Int) -> CentralChallengeRequest? {
        if let apiVersion = PumpStateSupplier.pumpApiVersion?(), apiVersion.greaterThan(KnownApiVersion.apiV3.value) {
            return nil
        } else {
            return createV1(appInstanceId: appInstanceId)
        }
    }

    private static func createV1(appInstanceId: Int) -> CentralChallengeRequest {
        let challenge = Bytes.getSecureRandom10Bytes()
        return CentralChallengeRequest(appInstanceId: appInstanceId, centralChallenge: challenge)
    }
}
