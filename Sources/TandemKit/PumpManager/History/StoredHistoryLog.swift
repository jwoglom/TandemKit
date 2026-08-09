import Foundation

/// One persisted pump history entry: the raw 26-byte record plus the columns worth indexing.
///
/// Mirrors ControlX2's `HistoryLogItem` (table `pumpdata_historylog`, primary key `(seqId, pumpSid)`).
/// The unparsed `cargo` is stored verbatim and re-parsed on demand, so a mapper fix or a later
/// clock-change correction can be re-applied without re-reading history from the pump.
public struct StoredHistoryLog: Equatable {
    /// Serial number of the pump the entry came from. Sequence numbers restart on a new pump, so
    /// every query is scoped by serial (ControlX2 calls this `pumpSid`).
    public let pumpSerial: UInt32
    /// Pump-assigned sequence number; unique per pump and monotonically increasing.
    public let sequenceNum: UInt32
    /// History log type discriminator, as parsed by `HistoryLogParser`.
    public let typeId: Int
    /// Raw pump clock: local wall-clock seconds since 2008-01-01, exactly as the pump reported it.
    /// Reconciled timestamps are never stored here — `HistoryTimestampReconciler` is a read-time
    /// transform, so a clock delta learned later still applies to entries stored earlier.
    public let pumpTimeSec: UInt32
    /// The unparsed 26-byte history log record.
    public let cargo: Data
    /// When this driver stored the entry, on the system clock.
    public let receivedAt: Date

    public init(
        pumpSerial: UInt32,
        sequenceNum: UInt32,
        typeId: Int,
        pumpTimeSec: UInt32,
        cargo: Data,
        receivedAt: Date = Date()
    ) {
        self.pumpSerial = pumpSerial
        self.sequenceNum = sequenceNum
        self.typeId = typeId
        self.pumpTimeSec = pumpTimeSec
        self.cargo = cargo
        self.receivedAt = receivedAt
    }

    public init(log: HistoryLog, pumpSerial: UInt32, receivedAt: Date = Date()) {
        self.init(
            pumpSerial: pumpSerial,
            sequenceNum: log.sequenceNum,
            typeId: log.typeId,
            pumpTimeSec: log.pumpTimeSec,
            cargo: log.cargo,
            receivedAt: receivedAt
        )
    }

    /// Re-parse the stored cargo into its concrete `HistoryLog` subclass.
    ///
    /// Parsing is cheap (a fixed 26-byte record) but not free; callers that render large lists
    /// should cache the results rather than calling this per row per redraw.
    public func parsed() -> HistoryLog {
        HistoryLogParser.parse(cargo)
    }

    /// The entry's time on the pump's own wall clock, with no clock-change reconciliation applied.
    public var pumpDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(pumpTimeSec))
    }
}
