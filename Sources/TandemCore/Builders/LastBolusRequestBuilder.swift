import Foundation

enum LastBolusRequestBuilder {
    static func create(apiVersion: ApiVersion?) -> (Message, Message.Type) {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return (LastBolusStatusV2Request(), LastBolusStatusV2Response.self)
        } else {
            return (LastBolusStatusRequest(), LastBolusStatusResponse.self)
        }
    }
}
