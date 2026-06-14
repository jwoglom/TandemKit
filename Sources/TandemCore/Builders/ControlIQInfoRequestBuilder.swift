import Foundation

enum ControlIQInfoRequestBuilder {
    static func create(apiVersion: ApiVersion?) -> (Message, Message.Type) {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return (ControlIQInfoV2Request(), ControlIQInfoV2Response.self)
        } else {
            return (ControlIQInfoV1Request(), ControlIQInfoV1Response.self)
        }
    }
}
