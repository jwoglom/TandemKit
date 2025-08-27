import Foundation

struct LastBolusStatusRequestBuilder {
    static func create(apiVersion: ApiVersion) -> Message {
        if apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return LastBolusStatusV2Request()
        } else {
            return LastBolusStatusRequest()
        }
    }
}
