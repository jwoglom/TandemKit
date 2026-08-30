import Foundation

/// The little that must survive a relaunch about this pump's history: how far the driver has
/// read, and the earliest date it may report events for.
///
/// Three scalars, no log records. The records live in the session-scoped `HistoryLogStore` and
/// are deliberately not persisted (#232 — the pump-manager layer stays storage-free, durable
/// dose storage is the host app's job). Without the watermark, though, every relaunch would
/// re-read everything the pump has written since the app was last open, which on a pump left
/// unattended for a day is thousands of entries. The watermark makes that read incremental; the
/// records behind it are re-read only when something in this session actually needs them.
public struct HistoryBackfillState: Equatable {
    /// The pump this bookkeeping describes. Sequence numbers are per-pump counters, so a serial
    /// mismatch invalidates every other field — see `matching(pumpSerial:now:)`.
    public var pumpSerial: UInt32

    /// Highest sequence number ever read from this pump, or nil if none has been. The resume
    /// point for an incremental read: the next one asks for `watermark + 1 ... last`.
    public var watermark: UInt32?

    /// Earliest date this driver will consider for this pump, and the deepest the backfill
    /// reads. Set at first sight and never moved: the host app's filter date marches forward to
    /// ≈now as this driver reports events (Trio returns `lastEventDate - 15min`), so tracking it
    /// would leave the walk with a target minutes old and IOB short. Emission combines the two —
    /// see `HistoryBackfillPlanner.emitFloor`.
    public var firstSeenFloor: Date?

    public init(pumpSerial: UInt32, watermark: UInt32? = nil, firstSeenFloor: Date? = nil) {
        self.pumpSerial = pumpSerial
        self.watermark = watermark
        self.firstSeenFloor = firstSeenFloor
    }

    /// Bookkeeping for a pump seen for the first time: nothing read yet, and a floor one
    /// deep-fetch lookback back.
    ///
    /// Not `now`. A pump can have been in use — bolusing from its own UI — for hours before this
    /// driver ever saw it, and that insulin is still acting. Flooring at `now` would hide it, and
    /// an under-reported IOB is the error direction that leads to over-delivery. Flooring one
    /// lookback back imports exactly the window whose insulin can still matter and nothing
    /// older, so a pump with months of history does not dump all of it into the host app.
    public init(firstSeenPumpSerial pumpSerial: UInt32, now: Date = Date()) {
        self.init(
            pumpSerial: pumpSerial,
            watermark: nil,
            firstSeenFloor: now.addingTimeInterval(-HistoryBackfillPlanner.deepFetchLookback)
        )
    }

    /// Advance the watermark to cover `range`. Never moves backward: a pump whose log was erased
    /// reports lower sequence numbers, and forgetting the high-water mark would re-read history
    /// already accounted for.
    public mutating func advanceWatermark(through sequenceNum: UInt32) {
        watermark = max(watermark ?? sequenceNum, sequenceNum)
    }

    /// This bookkeeping if it belongs to `pumpSerial`, otherwise fresh bookkeeping for the pump
    /// actually connected.
    ///
    /// A serial mismatch means a *replacement* pump: its sequence numbers count from its own
    /// history and say nothing about what this driver has read, and its pre-existing log may
    /// hold deliveries from a bench test or a previous owner. Both problems are handled by
    /// starting over with a floor at first sight, so nothing recorded before this pump
    /// entered service can reach the host app. Re-pairing the *same* pump keeps its bookkeeping,
    /// including the original floor, so the gap while the app was away is still reportable.
    public func matching(pumpSerial: UInt32, now: Date = Date()) -> HistoryBackfillState {
        guard self.pumpSerial == pumpSerial else {
            return HistoryBackfillState(firstSeenPumpSerial: pumpSerial, now: now)
        }
        return self
    }

    /// This bookkeeping, with the watermark dropped if the pump's newest entry sits below it —
    /// the log was erased and the counter restarted. Left alone, `watermark >= lastSequenceNum`
    /// reads as "nothing new" from then on and the pump is never read again. The floor is kept:
    /// same pump, same service, so only the read position is meaningless.
    public func resettingWatermarkIfAbove(lastSequenceNum: UInt32) -> HistoryBackfillState {
        guard let watermark, watermark > lastSequenceNum else {
            return self
        }
        var reset = self
        reset.watermark = nil
        return reset
    }
}

// MARK: - Raw representation

extension HistoryBackfillState: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let pumpSerial = rawValue["pumpSerial"] as? UInt32 else {
            return nil
        }

        // "emitFloor" is the key this field was first persisted under; read it so an existing
        // install keeps its first-seen date rather than re-flooring at now.
        let floor = (rawValue["firstSeenFloor"] as? TimeInterval)
            ?? (rawValue["emitFloor"] as? TimeInterval)

        self.init(
            pumpSerial: pumpSerial,
            watermark: rawValue["watermark"] as? UInt32,
            firstSeenFloor: floor.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = ["pumpSerial": pumpSerial]
        raw["watermark"] = watermark
        raw["firstSeenFloor"] = firstSeenFloor?.timeIntervalSinceReferenceDate
        return raw
    }
}
