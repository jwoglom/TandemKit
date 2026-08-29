import Foundation

public enum CurrentBatteryRequestBuilder {
    public static func create(apiVersion: ApiVersion?) -> any PumpRequest {
        if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return CurrentBatteryV2Request()
        } else {
            return CurrentBatteryV1Request()
        }
    }
}
