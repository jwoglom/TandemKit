import Foundation
@testable import TandemKit
import XCTest

final class CommandWatchdogTests: XCTestCase {
    private let queue = DispatchQueue(label: "test.commandWatchdog")

    func testCompletesOnceOnSuccessAndDoesNotTimeOut() {
        var outcomes: [Int] = []
        let exp = expectation(description: "result delivered")
        let extraDelivery = expectation(description: "second delivery")
        extraDelivery.isInverted = true
        // Long timeout: success must win and the timeout must be cancelled.
        let watchdog = CommandWatchdog<Int>(
            timeout: .seconds(10),
            timeoutResult: { 999 },
            queue: queue
        ) { value in
            outcomes.append(value)
            if outcomes.count == 1 { exp.fulfill() } else { extraDelivery.fulfill() }
        }

        watchdog.complete(42)
        wait(for: [exp], timeout: 1.0)

        wait(for: [extraDelivery], timeout: 0.2)
        XCTAssertEqual(outcomes, [42])
    }

    func testTimeoutFiresWhenNotCompleted() {
        var outcomes: [String] = []
        let exp = expectation(description: "timeout delivered")
        let watchdog = CommandWatchdog<String>(
            timeout: .milliseconds(40),
            timeoutResult: { "timed-out" },
            queue: queue
        ) { value in
            outcomes.append(value)
            exp.fulfill()
        }
        _ = watchdog // retain for the lifetime of the test

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(outcomes, ["timed-out"])
    }

    func testLateCompleteAfterTimeoutIsIgnored() {
        var outcomes: [String] = []
        let exp = expectation(description: "timeout delivered")
        let extraDelivery = expectation(description: "second delivery")
        extraDelivery.isInverted = true
        let watchdog = CommandWatchdog<String>(
            timeout: .milliseconds(40),
            timeoutResult: { "timed-out" },
            queue: queue
        ) { value in
            outcomes.append(value)
            if outcomes.count == 1 { exp.fulfill() } else { extraDelivery.fulfill() }
        }

        wait(for: [exp], timeout: 1.0)

        // A real completion that arrives after the watchdog already fired must be dropped.
        watchdog.complete("late-success")
        wait(for: [extraDelivery], timeout: 0.1)
        XCTAssertEqual(outcomes, ["timed-out"], "late completion must not double-deliver")
    }

    func testDuplicateCompleteDeliversOnlyFirst() {
        var outcomes: [Int] = []
        let extraDelivery = expectation(description: "second delivery")
        extraDelivery.isInverted = true
        let watchdog = CommandWatchdog<Int>(
            timeout: .seconds(10),
            timeoutResult: { -1 },
            queue: queue
        ) { value in
            outcomes.append(value)
            if outcomes.count > 1 { extraDelivery.fulfill() }
        }

        watchdog.complete(1)
        watchdog.complete(2)
        watchdog.complete(3)

        wait(for: [extraDelivery], timeout: 0.1)
        XCTAssertEqual(outcomes, [1])
    }

    func testConcurrentCompleteDeliversExactlyOnce() {
        let counter = DeliveryCounter()
        let extraDelivery = expectation(description: "second delivery")
        extraDelivery.isInverted = true
        let watchdog = CommandWatchdog<Int>(
            timeout: .seconds(10),
            timeoutResult: { -1 },
            queue: queue
        ) { _ in
            if counter.increment() > 1 { extraDelivery.fulfill() }
        }

        let group = DispatchGroup()
        for i in 0 ..< 100 {
            queue.async(group: group) {} // warm up
            DispatchQueue.global().async(group: group) {
                watchdog.complete(i)
            }
        }
        group.wait()

        wait(for: [extraDelivery], timeout: 0.1)
        XCTAssertEqual(counter.value, 1, "exactly one delivery under concurrent completion")
    }
}

private final class DeliveryCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int { lock.lock()
        defer { lock.unlock() }
        count += 1
        return count }

    var value: Int { lock.lock()
        defer { lock.unlock() }
        return count }
}
