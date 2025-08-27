import Foundation

struct CurrentBatteryRequestBuilder {
    static func create(apiVersion: ApiVersion) -> Message {
        if apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return CurrentBatteryV2Request()
        } else {
            return CurrentBatteryV1Request()
        }
    }
}
