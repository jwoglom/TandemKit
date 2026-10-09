import Foundation

/// Stable identity for a dose reported to the host app.
///
/// LoopKit turns `NewPumpEvent.raw` into `DoseEntry.syncIdentifier`, and the host app uses that to
/// decide whether an incoming event is a new dose or an update to one it already holds. In Trio the
/// same identifier drives the mutable-to-finalized upsert, and once a row is finalized it is never
/// revised — so an identifier that shifts between the optimistic report and the history-derived
/// confirmation produces a duplicate dose, not an update.
///
/// The identity therefore has to be something the *pump* assigns and repeats across every record of
/// the same delivery, not something the mapper derives:
///
/// * **Boluses** — `bolusId`, carried by `BolusActivatedHistoryLog`, `BolusCompletedHistoryLog`,
///   `BolexActivatedHistoryLog`/`BolexCompletedHistoryLog` and `BolusDeliveryHistoryLog`, and known
///   at command time from `BolusPermissionResponse`. Available in both phases, so an optimistically
///   reported bolus finalizes in place.
/// * **Temp rates** — `tempRateId`, carried by `TempRateActivatedHistoryLog` and
///   `TempRateCompletedHistoryLog`.
/// * **Everything else** — the pump assigns no id, so the log's own `sequenceNum` is the only
///   stable handle. Use `logSequence` only for events that are reported once, already final: a
///   sequence number is not knowable before the pump writes the record, so it cannot bridge an
///   optimistic report to its confirmation. Its one use is a basal correction, keyed on the
///   `BasalDeliveryHistoryLog` (279) whose cycle it reports, so there is at most one per 279.
///
/// `bolusId` and `tempRateId` are small pump-assigned counters that are eventually reused, so the
/// pump serial is part of every identifier, and callers must not treat an id as unique across the
/// lifetime of a pump — only within the reconciliation window. Because the serial carries that much
/// weight, no identifier can be built until it is actually known: see `PumpSerial`.
///
/// ## Wire format
///
/// ```
/// byte  0    format version (currently 1)
/// byte  1    scheme
/// bytes 2-5  pump serial, little-endian UInt32
/// bytes 6-9  identifier, little-endian UInt32
/// ```
///
/// **This encoding is frozen**: hosts persist it, so any change re-reports doses under new
/// identities. The live path does not use it yet (#344).
public enum HistoryLogSyncIdentifier {
    /// Which pump-assigned counter the identifier is built from. Values are persisted indirectly by
    /// the host app; never renumber them.
    public enum Scheme: UInt8 {
        /// `bolusId`, shared by every record of one bolus (standard, extended, quick, Control-IQ).
        case bolus = 1
        /// `tempRateId`, shared by a temp rate's activation and completion.
        case tempRate = 2
        /// The history log's own `sequenceNum`, for events the pump assigns no id to.
        case logSequence = 3
    }

    /// A pump serial known to be real, which is the only kind that may enter an identifier.
    ///
    /// `PumpState.pumpSerial` is optional and stays nil until a `PumpVersionResponse` arrives, so
    /// there is a window — first connection, or any session that reports a dose before the version
    /// poll completes — where the serial is simply not known. Substituting a placeholder there is
    /// the dangerous move: every dose minted under the placeholder claims an identity that the same
    /// pump will later re-mint under its real serial, so the confirmation no longer matches the
    /// optimistic report and the delivery is counted twice. Worse, two different pumps both fall
    /// back to the same placeholder, so their `bolusId` counters collide outright.
    ///
    /// Requiring this type means an unknown serial cannot be papered over with `?? 0` — the caller
    /// gets nil at construction and has to decide, and the correct decision is to fall back to the
    /// existing timestamp-based raw rather than emit an identifier that is wrong.
    ///
    /// Zero is rejected along with nil. No pump reports serial 0; `PumpVersionResponse.serialNumber`
    /// reads it straight out of the cargo, so 0 means an unparsed or absent response, and it is also
    /// exactly what a `?? 0` fallback would produce.
    public struct PumpSerial: Hashable {
        public let rawValue: UInt32

        /// Fails when the serial is unknown (nil) or the zero placeholder.
        public init?(_ rawValue: UInt32?) {
            guard let rawValue, rawValue != 0 else {
                return nil
            }
            self.rawValue = rawValue
        }
    }

    public static let formatVersion: UInt8 = 1

    /// Identifier bytes to hand to `NewPumpEvent(raw:)`.
    public static func data(scheme: Scheme, pumpSerial: PumpSerial, identifier: UInt32) -> Data {
        var data = Data(capacity: 10)
        data.append(formatVersion)
        data.append(scheme.rawValue)
        data.append(Bytes.toUint32(pumpSerial.rawValue))
        data.append(Bytes.toUint32(identifier))
        return data
    }

    /// Identity of a bolus, from the pump-assigned `bolusId`.
    public static func bolus(pumpSerial: PumpSerial, bolusId: Int) -> Data {
        data(scheme: .bolus, pumpSerial: pumpSerial, identifier: UInt32(clamping: bolusId))
    }

    /// Identity of a temp rate, from the pump-assigned `tempRateId`.
    public static func tempRate(pumpSerial: PumpSerial, tempRateId: Int) -> Data {
        data(scheme: .tempRate, pumpSerial: pumpSerial, identifier: UInt32(clamping: tempRateId))
    }

    /// Identity of an event the pump assigns no id to, from the history log's sequence number.
    /// Only valid for events reported once and already final — see the type documentation.
    public static func logSequence(pumpSerial: PumpSerial, sequenceNum: UInt32) -> Data {
        data(scheme: .logSequence, pumpSerial: pumpSerial, identifier: sequenceNum)
    }

    /// Reverses `data(scheme:pumpSerial:identifier:)`, for diagnostics and tests. Returns nil for
    /// anything that isn't a current-version identifier — including one carrying a serial this type
    /// would never have minted, since that cannot have come from us.
    public static func decode(_ data: Data) -> (scheme: Scheme, pumpSerial: PumpSerial, identifier: UInt32)? {
        guard data.count == 10,
              data[data.startIndex] == formatVersion,
              let scheme = Scheme(rawValue: data[data.startIndex + 1]),
              let pumpSerial = PumpSerial(littleEndianUInt32(data, at: 2))
        else {
            return nil
        }
        return (scheme, pumpSerial, littleEndianUInt32(data, at: 6))
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { value, byte in
            value | (UInt32(data[start + byte]) << (8 * byte))
        }
    }
}

public extension StoredHistoryLog {
    /// Identity for an event the pump assigns no id to, anchored on this entry's sequence number.
    /// Boluses and temp rates must use `HistoryLogSyncIdentifier.bolus`/`.tempRate` instead, so that
    /// the identifier survives the transition from an optimistic report to its history confirmation.
    ///
    /// Nil when the entry carries no usable pump serial — see `HistoryLogSyncIdentifier.PumpSerial`
    /// for why a placeholder serial is worse than no identifier at all.
    var logSequenceSyncIdentifier: Data? {
        guard let serial = HistoryLogSyncIdentifier.PumpSerial(pumpSerial) else {
            return nil
        }
        return HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: sequenceNum)
    }
}
