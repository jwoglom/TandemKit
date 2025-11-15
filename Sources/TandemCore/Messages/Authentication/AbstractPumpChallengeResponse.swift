import Foundation

/// Protocol defining common fields for pump challenge responses.
public protocol AbstractPumpChallengeResponse: Message {
    /// App instance identifier echoed back by the pump.
    var appInstanceId: Int { get }
}
