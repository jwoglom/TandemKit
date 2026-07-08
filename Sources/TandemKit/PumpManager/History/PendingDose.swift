//
//  PendingDose.swift
//  TandemKit
//
//  Ported from main's TandemPumpManagerState.swift (commit dd4fed5) into its own file
//  so the History pipeline is self-contained on the dev line. Used by HistoryReconciler
//  to match locally-tracked (optimistically-emitted) doses against history-derived events.
//

import Foundation
import LoopKit

public struct PendingDose: Codable, Equatable {
    public let syncIdentifier: String
    public let dose: DoseEntry
    public let requestedAt: Date
    /// The pump-assigned bolus id for this commanded bolus, when known. `HistoryReconciler` uses it as
    /// the strongest match anchor against history (unique + pump-authoritative) before falling back to
    /// type+time+amount. Nil for non-bolus pending doses and for entries persisted before this field
    /// existed (those still match via the fallback).
    public let bolusId: Int?

    public init(syncIdentifier: String, dose: DoseEntry, requestedAt: Date, bolusId: Int? = nil) {
        self.syncIdentifier = syncIdentifier
        self.dose = dose
        self.requestedAt = requestedAt
        self.bolusId = bolusId
    }
}
