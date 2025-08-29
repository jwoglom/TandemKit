//
//  AbstractPumpChallengeResponse.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's AbstractPumpChallengeResponse abstract class.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/authentication/AbstractPumpChallengeResponse.java
//

import Foundation

/// Protocol defining common fields for pump challenge responses.
public protocol AbstractPumpChallengeResponse: Message {
    /// App instance identifier echoed back by the pump.
    var appInstanceId: Int { get }
}

