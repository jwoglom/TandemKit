import Foundation
import LoopKit
@testable import TandemKit

/// A pure-Swift model of what a host stores when it receives
/// `pumpManager(_:hasNewPumpEvents:lastReconciliation:replacePendingEvents:completion:)`.
///
/// Conformance tests feed the delegate's journal into an oracle (`MockPumpManagerDelegate.feed(_:)`)
/// and assert on the oracle's stored doses rather than on the raw delegate calls: a report can be
/// individually well-formed and still leave the host with a duplicate or a vanished dose.
///
/// `now` is the host's idea of the current time when the batch arrived. LoopKit reads `Date()` for
/// this; the journal supplies the driver clock's `now` when one is injected, so the oracle sees the
/// same instant the driver used to date its doses.
protocol DoseOracle: AnyObject {
    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, now: Date)
}
