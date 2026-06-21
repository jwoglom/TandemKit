import Foundation
@testable import TandemCore
import XCTest

final class TandemDispatchGroupTests: XCTestCase {
    func testLeaveBeforeTimeoutReturnsPayload() {
        let group = TandemDispatchGroup()
        group.enter()

        let payload = Data([0x01, 0x02, 0x03])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            group.leave(payload)
        }

        let result = group.wait(timeout: .now() + 2.0)
        XCTAssertEqual(result, payload)
    }

    func testTimeoutReturnsNil() {
        let group = TandemDispatchGroup()
        group.enter()

        // No leave/cancel: must time out and report nil.
        let result = group.wait(timeout: .now() + 0.05)
        XCTAssertNil(result)
    }

    func testEmptyDataCompletionIsDistinctFromTimeout() {
        // The key correctness property of the rewrite: a producer that legitimately completes with
        // empty Data (e.g. a write acknowledgement) must be distinguishable from a timeout. Both
        // would have collapsed to nil under a naive implementation.
        let group = TandemDispatchGroup()
        group.enter()
        group.leave(Data())

        let result = group.wait(timeout: .now() + 2.0)
        XCTAssertNotNil(result, "empty-Data completion must not look like a timeout")
        XCTAssertEqual(result, Data())
    }

    func testCancelUnblocksWithNil() {
        let group = TandemDispatchGroup()
        group.enter()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            group.cancel()
        }

        let result = group.wait(timeout: .now() + 2.0)
        XCTAssertNil(result, "cancel must unblock the waiter with no payload")
    }

    func testDoubleLeaveDoesNotCrashAndKeepsFirstPayload() {
        let group = TandemDispatchGroup()
        group.enter()

        let first = Data([0xAA])
        group.leave(first)
        group.leave(Data([0xBB])) // must be a no-op, must not crash

        XCTAssertEqual(group.wait(timeout: .now() + 2.0), first)
    }

    func testLateLeaveAfterTimeoutIsNoOp() {
        let group = TandemDispatchGroup()
        group.enter()

        XCTAssertNil(group.wait(timeout: .now() + 0.05)) // times out

        // A delegate callback arriving after the timeout must not crash or strand a signal.
        group.leave(Data([0x09]))
        group.cancel()
    }

    func testConcurrentLeaveDeliversExactlyOnce() {
        let group = TandemDispatchGroup()
        group.enter()

        let iterations = 50
        let start = DispatchSemaphore(value: 0)
        for i in 0 ..< iterations {
            DispatchQueue.global().async {
                start.wait()
                group.leave(Data([UInt8(i & 0xFF)]))
            }
        }
        for _ in 0 ..< iterations { start.signal() }

        // Exactly one of the concurrent leaves wins; wait must return some payload, never hang/crash.
        XCTAssertNotNil(group.wait(timeout: .now() + 2.0))
    }
}
