import Foundation

struct PumpFeaturesRequestBuilder {
    static func create(apiVersion: ApiVersion) -> Message {
        if apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return PumpFeaturesV2Request()
        } else {
            return PumpFeaturesV1Request()
        }
    }
}
