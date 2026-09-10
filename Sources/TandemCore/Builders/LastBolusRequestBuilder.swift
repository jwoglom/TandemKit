import Foundation

enum LastBolusRequestBuilder {
    /// Picks the newest last-bolus message the pump declares support for. A pump whose model or
    /// API version is not yet known falls back to the legacy request, which every pump answers.
    static func create(apiVersion: ApiVersion?, pumpModel: PumpModel? = nil) -> any PumpRequest {
        if LastBolusStatusV3Request.props.isSupported(pumpModel: pumpModel, apiVersion: apiVersion) {
            return LastBolusStatusV3Request()
        } else if LastBolusStatusV2Request.props.isSupported(pumpModel: pumpModel, apiVersion: apiVersion) {
            return LastBolusStatusV2Request()
        } else {
            return LastBolusStatusRequest()
        }
    }
}
