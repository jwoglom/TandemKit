//
//  OSLog.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//
//  Basis: PumpKit OSLog.swift
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

#if canImport(os)
import os.log

extension OSLog {
    public convenience init(category: String) {
        self.init(subsystem: "com.jwoglom.TandemKit", category: category)
    }

    public func debug(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .debug, args)
    }

    public func info(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .info, args)
    }

    public func `default`(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .default, args)
    }

    public func error(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .error, args)
    }

    private func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        switch args.count {
        case 0:
            os_log(message, log: self, type: type)
        case 1:
            os_log(message, log: self, type: type, args[0])
        case 2:
            os_log(message, log: self, type: type, args[0], args[1])
        case 3:
            os_log(message, log: self, type: type, args[0], args[1], args[2])
        case 4:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3])
        case 5:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3], args[4])
        default:
            os_log(message, log: self, type: type, args)
        }
    }
}
#else
public struct OSLog {
    public init(subsystem: String = "com.jwoglom.TandemKit", category: String) {}
    public init(category: String) { self.init(subsystem: "com.jwoglom.TandemKit", category: category) }
    public func debug(_ message: StaticString, _ args: CVarArg...) {}
    public func info(_ message: StaticString, _ args: CVarArg...) {}
    public func `default`(_ message: StaticString, _ args: CVarArg...) {}
    public func error(_ message: StaticString, _ args: CVarArg...) {}
}
#endif
