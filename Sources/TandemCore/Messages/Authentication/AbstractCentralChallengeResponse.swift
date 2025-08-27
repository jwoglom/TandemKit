//
//  AbstractCentralChallengeResponse.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Mirrors PumpX2's AbstractCentralChallengeResponse to expose the
//  common fields for responses to central challenge messages.
//

import Foundation

/// Protocol defining common fields for central challenge responses.
public protocol AbstractCentralChallengeResponse: Message {
    /// App instance identifier echoed back by the pump.
    var appInstanceId: Int { get }
}

