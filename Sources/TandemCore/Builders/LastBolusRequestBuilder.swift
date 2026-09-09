import Foundation

enum LastBolusRequestBuilder {
    static func create(apiVersion: ApiVersion?, pumpModel: PumpModel? = nil) -> any PumpRequest {
        if LastBolusStatusV3Request.props.isSupported(pumpModel: pumpModel, apiVersion: apiVersion) {
            return LastBolusStatusV3Request()
        } else if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
            return LastBolusStatusV2Request()
        } else {
            return LastBolusStatusRequest()
        }
    }
}
