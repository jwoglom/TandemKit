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

    public init(syncIdentifier: String, dose: DoseEntry, requestedAt: Date) {
        self.syncIdentifier = syncIdentifier
        self.dose = dose
        self.requestedAt = requestedAt
    }
}
