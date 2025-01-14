//
//  TandemPumpManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import HealthKit
import LoopKit
import os.log

public class TandemPumpManager : DeviceManager {
    public static var localizedTitle: String = "TandemPumpManager"
    public static var managerIdentifier: String = "Tandem"
    
    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    
    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }
    
    private var pumpComm: PumpComm {
            get {
                return tandemPump.pumpComm
            }
            set {
                tandemPump.pumpComm = newValue
            }
        }
    
    public init(state: TandemPumpManagerState) {
        self.lockedState = Locked(state)
        self.tandemPump = TandemPump(state.pumpState)

        self.tandemPump.delegate = self

        self.pumpComms.delegate = self
        self.pumpComms.messageLogger = self
    }
    
    public required init?(rawState: PumpManager.RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else
        {
            return nil
        }
        
        self.init(state: state)
    }
    
    public var rawState: RawStateValue
    
    public var debugDescription: String
    
    
}
