//
//  TimeInterval.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

//
//  Basis: OmniBLE
//  Created by Nathan Racklyeft on 1/9/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public extension TimeInterval {

    public static func days(_ days: Double) -> TimeInterval {
        return self.init(days: days)
    }

    public static func hours(_ hours: Double) -> TimeInterval {
        return self.init(hours: hours)
    }

    public static func minutes(_ minutes: Int) -> TimeInterval {
        return self.init(minutes: Double(minutes))
    }

    public static func minutes(_ minutes: Double) -> TimeInterval {
        return self.init(minutes: minutes)
    }

    public static func seconds(_ seconds: Double) -> TimeInterval {
        return self.init(seconds)
    }

    public static func milliseconds(_ milliseconds: Double) -> TimeInterval {
        return self.init(milliseconds / 1000)
    }

    public init(days: Double) {
        self.init(hours: days * 24)
    }

    public init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    public init(minutes: Double) {
        self.init(minutes * 60)
    }

    public init(seconds: Double) {
        self.init(seconds)
    }

    public init(milliseconds: Double) {
        self.init(milliseconds / 1000)
    }

    public var milliseconds: Double {
        return self * 1000
    }

    public init(hundredthsOfMilliseconds: Double) {
        self.init(hundredthsOfMilliseconds / 100000)
    }

    public var hundredthsOfMilliseconds: Double {
        return self * 100000
    }

    public var minutes: Double {
        return self / 60.0
    }

    public var hours: Double {
        return minutes / 60.0
    }

    public var days: Double {
        return hours / 24.0
    }

}
