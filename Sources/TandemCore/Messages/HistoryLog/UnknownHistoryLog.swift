//
//  UnknownHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Fallback history log entry used when a specific type is not implemented.
//

import Foundation

/// History log type used when a specific implementation is unavailable.
public class UnknownHistoryLog: HistoryLog {
    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }
}

