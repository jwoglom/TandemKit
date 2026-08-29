import Foundation

enum ControlIQInfoRequestBuilder {
    static func create(apiVersion: ApiVersion?) -> any PumpRequest {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return ControlIQInfoV2Request()
        } else {
            return ControlIQInfoV1Request()
        }
    }
}
