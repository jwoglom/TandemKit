import Foundation

/// Selects the insulin-on-board request matching the pump's Control-IQ support.
///
/// Mirrors PumpX2's `IOBRequestBuilder`: the pump reports IOB under two different opcodes
/// depending on whether Control-IQ is present, and the wrong one goes unanswered.
public enum IOBRequestBuilder {
    public static func create(controlIQSupported: Bool) -> (Message, Message.Type) {
        if controlIQSupported {
            return (ControlIQIOBRequest(), ControlIQIOBResponse.self)
        } else {
            return (NonControlIQIOBRequest(), NonControlIQIOBResponse.self)
        }
    }
}
