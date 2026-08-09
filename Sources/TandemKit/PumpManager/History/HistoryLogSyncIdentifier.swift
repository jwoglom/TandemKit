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
/// * **Everything else** — the pump assigns no id (notably `BasalRateChangeHistoryLog` and
///   `BasalDeliveryHistoryLog`, which describe scheduled-basal changes), so the log's own
///   `sequenceNum` is the only stable handle. Use `logSequence` only for events that are reported
///   once, already final: a sequence number is not knowable before the pump writes the record, so it
///   cannot bridge an optimistic report to its confirmation.
///
/// `bolusId` and `tempRateId` are small pump-assigned counters that are eventually reused, so the
/// pump serial is part of every identifier, and callers must not treat an id as unique across the
/// lifetime of a pump — only within the reconciliation window.
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
/// **This encoding is frozen.** Every byte feeds the identifier the host app has already persisted;
/// changing the layout, the scheme numbering or the version orphans finalized rows and re-reports
/// their doses under new identities, which double-counts insulin. A new format version must only be
/// introduced alongside a migration story for events already in flight.
///
/// Nothing emits these identifiers yet — `NewPumpEvent`'s raw values are still built from the dose
/// type, volume and timestamp. Adopting them is a separate change; see the type's tests for the
/// golden values that must not move once it happens.
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

    public static let formatVersion: UInt8 = 1

    /// Identifier bytes to hand to `NewPumpEvent(raw:)`.
    public static func data(scheme: Scheme, pumpSerial: UInt32, identifier: UInt32) -> Data {
        var data = Data(capacity: 10)
        data.append(formatVersion)
        data.append(scheme.rawValue)
        data.append(Bytes.toUint32(pumpSerial))
        data.append(Bytes.toUint32(identifier))
        return data
    }

    /// Identity of a bolus, from the pump-assigned `bolusId`.
    public static func bolus(pumpSerial: UInt32, bolusId: Int) -> Data {
        data(scheme: .bolus, pumpSerial: pumpSerial, identifier: UInt32(clamping: bolusId))
    }

    /// Identity of a temp rate, from the pump-assigned `tempRateId`.
    public static func tempRate(pumpSerial: UInt32, tempRateId: Int) -> Data {
        data(scheme: .tempRate, pumpSerial: pumpSerial, identifier: UInt32(clamping: tempRateId))
    }

    /// Identity of an event the pump assigns no id to, from the history log's sequence number.
    /// Only valid for events reported once and already final — see the type documentation.
    public static func logSequence(pumpSerial: UInt32, sequenceNum: UInt32) -> Data {
        data(scheme: .logSequence, pumpSerial: pumpSerial, identifier: sequenceNum)
    }

    /// Reverses `data(scheme:pumpSerial:identifier:)`, for diagnostics and tests. Returns nil for
    /// anything that isn't a current-version identifier.
    public static func decode(_ data: Data) -> (scheme: Scheme, pumpSerial: UInt32, identifier: UInt32)? {
        guard data.count == 10,
              data[data.startIndex] == formatVersion,
              let scheme = Scheme(rawValue: data[data.startIndex + 1])
        else {
            return nil
        }
        return (scheme, littleEndianUInt32(data, at: 2), littleEndianUInt32(data, at: 6))
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { value, byte in
            value | (UInt32(data[start + byte]) << (8 * byte))
        }
    }
}
