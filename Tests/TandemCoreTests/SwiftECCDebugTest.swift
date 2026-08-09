import Foundation
@testable import TandemKit
import XCTest

#if canImport(SwiftECC) && canImport(BigInt)
    import BigInt
    import SwiftECC

    final class SwiftECCDebugTest: XCTestCase {
        func testSwiftECCOperationsStepByStep() throws {
            print("\n🔍 Testing SwiftECC operations step by step...")

            // Step 1: Domain initialization
            print("1️⃣ Creating Domain...")
            let start1 = Date()
            let domain = Domain.instance(curve: .EC256r1)
            print("   ✅ Domain created in \(Date().timeIntervalSince(start1))s")

            // Step 2: Generate a random scalar
            print("2️⃣ Generating random scalar...")
            let start2 = Date()
            let randomBytes = JpakeAuthBuilder.defaultRandom(32)
            let randomScalar = BInt(magnitude: [UInt8](randomBytes))
            print("   ✅ Random scalar created in \(Date().timeIntervalSince(start2))s")

            // Step 3: Single point multiplication
            print("3️⃣ Single point multiplication...")
            let start3 = Date()
            let point1 = try domain.multiplyPoint(domain.g, BInt(magnitude: [42]))
            print("   ✅ Point multiplication in \(Date().timeIntervalSince(start3))s")

            // Step 4: Multiple point multiplications (what getRound1 does)
            print("4️⃣ Multiple point multiplications (4x)...")
            let start4 = Date()
            for i in 1 ... 4 {
                let scalar = BInt(magnitude: [UInt8](JpakeAuthBuilder.defaultRandom(32)))
                _ = try domain.multiplyPoint(domain.g, scalar)
                let elapsed = Date().timeIntervalSince(start4)
                print("   ⏱️  Iteration \(i): \(elapsed)s total")
            }
            let elapsed4 = Date().timeIntervalSince(start4)
            print("   ✅ 4 multiplications in \(elapsed4)s")

            // Step 5: Point encoding (used in getRound1)
            print("5️⃣ Point encoding...")
            let start5 = Date()
            let encoded = try domain.encodePoint(point1)
            print("   ✅ Point encoding in \(Date().timeIntervalSince(start5))s, size: \(encoded.count) bytes")

            // Step 6: Point addition (used in getRound2)
            print("6️⃣ Point addition...")
            let start6 = Date()
            let point2 = try domain.multiplyPoint(domain.g, BInt(magnitude: [43]))
            let sumPoint = try domain.addPoints(point1, point2)
            print("   ✅ Point addition in \(Date().timeIntervalSince(start6))s")

            print("\n✅ All individual operations completed successfully")
        }

        func testRandomScalarOperation() throws {
            print("\n🔍 Testing randomScalar operation (modulo domain.order)...")

            let domain = Domain.instance(curve: .EC256r1)
            print("📊 domain.order: \(domain.order)")

            let start = Date()
            for i in 1 ... 10 {
                let randomBytes = JpakeAuthBuilder.defaultRandom(32)
                var n = BInt(magnitude: [UInt8](randomBytes))
                n = n % (domain.order - 1) + 1
                let elapsed = Date().timeIntervalSince(start)
                print("   ⏱️  Iteration \(i): scalar mod operation in \(elapsed)s total")
            }
            let elapsed = Date().timeIntervalSince(start)
            print("✅ 10 randomScalar operations in \(elapsed)s")
        }

        func testEcJpakeInitialization() throws {
            print("\n🔍 Testing EcJpake initialization...")

            // Pre-warm Domain before creating EcJpake
            print("0️⃣ Pre-warming Domain.instance()...")
            let preDomain = Domain.instance(curve: .EC256r1)
            print("   Domain.g: \(preDomain.g)")
            print("   Domain.order: \(preDomain.order)")

            // Do a test multiply to fully initialize
            print("   Performing test multiply...")
            _ = try preDomain.multiplyPoint(preDomain.g, BInt(magnitude: [1, 2, 3]))
            print("   ✅ Domain pre-warmed")

            print("1️⃣ Creating EcJpake instance...")
            let start = Date()
            let jpake = EcJpake(
                role: .client,
                password: Data("123456".utf8),
                random: JpakeAuthBuilder.defaultRandom
            )
            print("   ✅ EcJpake created in \(Date().timeIntervalSince(start))s")

            print("2️⃣ Accessing other properties...")
            _ = jpake.role
            _ = jpake.myId
            print("   ✅ Properties accessible")

            print("4️⃣ About to call getRound1()...")
            fflush(stdout) // Force flush before potentially blocking call

            let result = jpake.getRound1()

            print("5️⃣ getRound1() returned!")
            print("   📦 Result size: \(result.count) bytes")

            XCTAssertEqual(result.count, 330)
        }

        func testActualGetRound1() throws {
            print("\n🔍 Testing actual EcJpake.getRound1()...")
            fflush(stdout)

            print("📍 About to create EcJpake instance...")
            fflush(stdout)

            let start = Date()
            let jpake = EcJpake(
                role: .client,
                password: Data("123456".utf8),
                random: JpakeAuthBuilder.defaultRandom
            )

            print("⏱️  EcJpake created, now calling getRound1()...")
            fflush(stdout)

            // Try accessing a property first
            print("🔍 Accessing jpake.role: \(jpake.role)")
            fflush(stdout)

            // Try accessing domain.g directly
            print("🔍 About to access jpake.domain.g...")
            fflush(stdout)
            let g = jpake.domain.g
            print("🔍 Successfully accessed domain.g: \(g)")
            fflush(stdout)

            let result = jpake.getRound1()

            let elapsed = Date().timeIntervalSince(start)
            print("✅ getRound1() completed in \(elapsed)s")
            print("📦 Result size: \(result.count) bytes")

            XCTAssertEqual(result.count, 330)
        }
    }

#endif
