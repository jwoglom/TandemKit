import Harmonize
import SwiftSyntax
import XCTest

final class UnitTestsDoNotSleep: XCTestCase {
    func testUnitTestsDoNotSleep() {
        let sleeps = TandemHarmonize.unitTestCode.sources().flatMap { file in
            file.occurrences(of: FunctionCallExprSyntax.self).filter {
                Self.sleepCalls.contains($0.node.calledExpression.trimmedDescription)
            }
        }

        sleeps.assertEmpty(rule: Self.rule)
    }

    private static let sleepCalls: Set<String> = ["sleep", "usleep", "Thread.sleep", "Task.sleep"]


    private static let rule = Rule(
        description: "Unit tests never sleep.",
        rationale: """
            A sleep guesses how long a timer, the command queue or a delegate hop takes. It costs its full delay on
            every run and still fails on a loaded CI runner. A test that needs something to happen should wait for it;
            one that needs time to pass should own the clock.
            """,
        fixHint: """
            Wait on an XCTestExpectation for the event. To prove something does not happen, use an inverted
            expectation. For time-driven behaviour, inject a TandemClock or the DispatchQueue the code schedules on.
            """,
        badExample: "watchdog.complete(42)\nThread.sleep(forTimeInterval: 0.2)\nXCTAssertEqual(outcomes, [42])",
        goodExample: "let timeout = expectation(description: \"timeout\")\ntimeout.isInverted = true\nwait(for: [timeout], timeout: 0.2)"
    )
}
