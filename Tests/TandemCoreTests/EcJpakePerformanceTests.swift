//
//  EcJpakePerformanceTests.swift
//  TandemKit
//
//  Tests to identify the SwiftECC blocking issue
//

import XCTest
@testable import TandemCore
import Foundation

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
import SwiftECC
import BigInt

final class EcJpakePerformanceTests: XCTestCase {

    func testNonBlockingRandomPerformance() throws {
        // Test that NonBlockingRandom doesn't block
        let start = Date()

        for _ in 0..<100 {
            let data = JpakeAuthBuilder.defaultRandom(32)
            XCTAssertEqual(data.count, 32)
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "NonBlockingRandom took too long: \(elapsed)s")

        print("✅ NonBlockingRandom: 100 iterations in \(elapsed)s")
    }

    func testEcJpakeGetRound1Performance() throws {
        // Test if getRound1() completes in reasonable time
        print("🔍 Testing EcJpake.getRound1() performance...")
        print("  ⏱️  Starting getRound1() synchronously on test thread...")

        let start = Date()

        let jpake = EcJpake(
            role: .client,
            password: Data("123456".utf8),
            random: JpakeAuthBuilder.defaultRandom
        )

        print("  📊 EcJpake initialized, calling getRound1()...")
        let result = jpake.getRound1()

        let elapsed = Date().timeIntervalSince(start)
        print("  ✅ getRound1() completed in \(elapsed)s")
        print("  📦 Result size: \(result.count) bytes")

        XCTAssertEqual(result.count, 330, "getRound1 should return 330 bytes (2 key pairs)")
        XCTAssertLessThan(elapsed, 2.0, "getRound1 should complete in under 2 seconds")
    }

    func testJpakeAuthBuilderNextRequestPerformance() throws {
        // Test the full nextRequest() path
        print("🔍 Testing JpakeAuthBuilder.nextRequest() performance...")

        let expectation = expectation(description: "nextRequest completes")
        var completed = false
        var request: Message?
        var error: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            print("  ⏱️  Starting nextRequest()...")
            let start = Date()

            let builder = JpakeAuthBuilder(pairingCode: "123456")
            request = builder.nextRequest()

            let elapsed = Date().timeIntervalSince(start)
            print("  ✅ nextRequest() completed in \(elapsed)s")
            print("  📦 Request type: \(type(of: request))")

            completed = true
            expectation.fulfill()
        }

        // Wait with a timeout
        wait(for: [expectation], timeout: 10.0)

        XCTAssertTrue(completed, "nextRequest should complete")
        XCTAssertNil(error, "nextRequest should not throw")
        XCTAssertNotNil(request, "nextRequest should return a message")
        XCTAssertTrue(request is Jpake1aRequest, "First request should be Jpake1aRequest")
    }

    func testSwiftECCDomainInitialization() throws {
        // Test if Domain.instance() is the slow part
        print("🔍 Testing SwiftECC Domain initialization...")

        let start = Date()

        // This might be the blocking call
        let domain = Domain.instance(curve: .EC256r1)

        let elapsed = Date().timeIntervalSince(start)
        print("  ✅ Domain.instance() completed in \(elapsed)s")

        XCTAssertLessThan(elapsed, 1.0, "Domain initialization took too long: \(elapsed)s")

        // Test point operations
        let start2 = Date()
        let _ = try domain.multiplyPoint(domain.g, BInt(magnitude: [42]))
        let elapsed2 = Date().timeIntervalSince(start2)

        print("  ✅ First multiplyPoint() in \(elapsed2)s")
        XCTAssertLessThan(elapsed2, 1.0, "Point multiplication took too long: \(elapsed2)s")
    }

    func testMultipleGetRound1Calls() throws {
        // Test if subsequent calls are faster (cache warming)
        print("🔍 Testing multiple getRound1() calls...")

        var times: [TimeInterval] = []

        for i in 0..<3 {
            let start = Date()

            let jpake = EcJpake(
                role: .client,
                password: Data("12345\(i)".utf8),
                random: JpakeAuthBuilder.defaultRandom
            )

            let _ = jpake.getRound1()
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)

            print("  ⏱️  Call \(i+1): \(elapsed)s")
        }

        // Check if times improve (indicating cache warmup)
        if times.count >= 2 {
            print("  📊 First call: \(times[0])s, Second call: \(times[1])s")
            if times[1] < times[0] * 0.5 {
                print("  ✅ Subsequent calls are faster (cache warmup detected)")
            }
        }
    }
}

#endif
