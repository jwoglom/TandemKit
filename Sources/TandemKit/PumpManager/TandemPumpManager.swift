//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

#if canImport(HealthKit)

import Foundation
import LoopKit
import TandemCore

public class TandemPumpManager: DeviceManager, PumpManager {
    public static var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    public var delegateQueue: DispatchQueue! {
        get { pumpDelegate.queue }
        set { pumpDelegate.queue = newValue }
    }

    public var rawState: PumpManager.RawStateValue

    public required init?(rawState: PumpManager.RawStateValue) {
        self.rawState = rawState
    }

    public var debugDescription: String {
        "TandemPumpManager()"
    }
}

#endif
