import Foundation

/// Protocol defining common fields for central challenge responses.
public protocol AbstractCentralChallengeResponse: Message {
    /// App instance identifier echoed back by the pump.
    var appInstanceId: Int { get }
}
