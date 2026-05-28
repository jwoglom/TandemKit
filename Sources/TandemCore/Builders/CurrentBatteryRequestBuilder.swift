import Foundation

public enum CurrentBatteryRequestBuilder {
    public static func create(apiVersion: ApiVersion?) -> (Message, Message.Type) {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return (CurrentBatteryV2Request(), CurrentBatteryV2Response.self)
        } else {
            return (CurrentBatteryV1Request(), CurrentBatteryV1Response.self)
        }
    }
}
