import Foundation

public extension MessageProps {
    /// Whether a pump of this model and API version can be expected to handle the message.
    ///
    /// Messages declare `minApi` and `supportedDevices`, but nothing consulted them until now, so
    /// the UI could offer writes that the pump was never going to answer -- Control-IQ sleep
    /// schedules being the case that prompted this (they are Mobi-only, from API 3.5).
    ///
    /// An unknown model or API version answers false: the pump has not been interrogated yet, so
    /// support cannot be confirmed until the next sync.
    func isSupported(pumpModel: PumpModel?, apiVersion: ApiVersion?) -> Bool {
        guard let pumpModel, let apiVersion else {
            return false
        }
        guard supportedDevices.value.contains(pumpModel) else {
            return false
        }
        return apiVersion == minApi.value || apiVersion.greaterThan(minApi)
    }
}
