#if !canImport(ObjectiveC)
import Foundation
import XCTest

// swift-corelibs-xctest has no XCTExpectFailure. These cover the block forms this suite uses, with
// Apple's strictness: a strict block that records no failure fails the test. Failures reach
// ExpectedFailureScope through FaketandemIntegrationTestCase.recordFailure.

enum XCTExpectedFailure {
    final class Options {
        var isStrict = true
    }
}

func XCTExpectFailure<R>(
    _ failureReason: String? = nil,
    strict: Bool = true,
    file: StaticString = #filePath,
    line: UInt = #line,
    failingBlock: () throws -> R
) rethrows -> R {
    let options = XCTExpectedFailure.Options()
    options.isStrict = strict
    return try XCTExpectFailure(failureReason, options: options, file: file, line: line, failingBlock: failingBlock)
}

func XCTExpectFailure<R>(
    _ failureReason: String?,
    options: XCTExpectedFailure.Options,
    file: StaticString = #filePath,
    line: UInt = #line,
    failingBlock: () throws -> R
) rethrows -> R {
    let scope = ExpectedFailureScope(reason: failureReason ?? "")
    ExpectedFailureScope.push(scope)
    let result: R
    do {
        result = try failingBlock()
    } catch {
        ExpectedFailureScope.pop(scope)
        throw error
    }
    ExpectedFailureScope.pop(scope)
    if options.isStrict, scope.absorbed == 0 {
        XCTFail("Expected failure did not occur (unexpected pass): \(scope.reason)", file: file, line: line)
    }
    return result
}

final class ExpectedFailureScope {
    private static let lock = NSLock()
    private static var stack: [ExpectedFailureScope] = []

    let reason: String
    private(set) var absorbed = 0

    init(reason: String) {
        self.reason = reason
    }

    static func push(_ scope: ExpectedFailureScope) {
        lock.lock()
        stack.append(scope)
        lock.unlock()
    }

    static func pop(_ scope: ExpectedFailureScope) {
        lock.lock()
        stack.removeAll { $0 === scope }
        lock.unlock()
    }

    /// True when an expected-failure block is running, which then owns the failure.
    static func absorb(_ description: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let scope = stack.last else { return false }
        scope.absorbed += 1
        print("Expected failure: \(description) Reason: \(scope.reason)")
        return true
    }
}
#endif
