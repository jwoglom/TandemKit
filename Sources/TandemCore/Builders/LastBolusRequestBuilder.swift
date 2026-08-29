import Foundation

enum LastBolusRequestBuilder {
    static func create(apiVersion: ApiVersion?) -> any PumpRequest {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return LastBolusStatusV2Request()
        } else {
            return LastBolusStatusRequest()
        }
    }
}
