import Foundation

/// Selects the insulin-on-board request matching the pump's Control-IQ support.
///
/// Mirrors PumpX2's `IOBRequestBuilder`: the pump reports IOB under two different opcodes
/// depending on whether Control-IQ is present, and the wrong one goes unanswered.
public enum IOBRequestBuilder {
    public static func create(controlIQSupported: Bool) -> any PumpRequest {
        if controlIQSupported {
            return ControlIQIOBRequest()
        } else {
            return NonControlIQIOBRequest()
        }
    }
}
