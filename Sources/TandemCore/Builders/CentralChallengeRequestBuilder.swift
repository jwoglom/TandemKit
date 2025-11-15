import Foundation

public enum CentralChallengeRequestBuilder {
    public static func create(appInstanceId: Int) -> CentralChallengeRequest? {
        let apiVersion = PumpStateSupplier.currentPumpApiVersion()
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV3_2.value) {
            return nil
        } else {
            return createV1(appInstanceId: appInstanceId)
        }
    }

    private static func createV1(appInstanceId: Int) -> CentralChallengeRequest {
        let challenge = Bytes.getSecureRandom8Bytes()
        return CentralChallengeRequest(appInstanceId: appInstanceId, centralChallenge: challenge)
    }
}
