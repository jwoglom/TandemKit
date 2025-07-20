import Foundation

struct ControlIQInfoRequestBuilder {
    static func create(apiVersion: ApiVersion) -> Message {
        if apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return ControlIQInfoV2Request()
        } else {
            return ControlIQInfoV1Request()
        }
    }
}
