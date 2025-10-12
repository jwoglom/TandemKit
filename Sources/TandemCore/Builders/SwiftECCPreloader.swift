//
//  SwiftECCPreloader.swift
//  TandemKit
//
//  Pre-initializes SwiftECC to avoid blocking during JPAKE pairing
//

import Foundation

#if canImport(SwiftECC) && canImport(BigInt)
import SwiftECC
import BigInt

/// Pre-loads SwiftECC resources to avoid first-use blocking
public final class SwiftECCPreloader {
    public static let shared = SwiftECCPreloader()

    private var isPreloaded = false
    private let lock = NSLock()

    private init() {}

    /// Pre-initialize SwiftECC on a background thread
    ///
    /// Call this early in the app lifecycle (e.g., in AppDelegate or during startup)
    /// to ensure SwiftECC resources are ready before pairing attempts.
    public func preload(completion: (() -> Void)? = nil) {
        lock.lock()
        if isPreloaded {
            lock.unlock()
            completion?()
            return
        }
        lock.unlock()

        DispatchQueue.global(qos: .utility).async {
            print("[SwiftECCPreloader] Starting preload...")
            let start = Date()

            // Initialize the EC256r1 domain (used by JPAKE)
            let domain = Domain.instance(curve: .EC256r1)

            // Perform a test point multiplication to warm up the library
            let testPriv = BInt(magnitude: [42])
            _ = try? domain.multiplyPoint(domain.g, testPriv)

            let elapsed = Date().timeIntervalSince(start)
            print("[SwiftECCPreloader] Preload completed in \(elapsed)s")

            self.lock.lock()
            self.isPreloaded = true
            self.lock.unlock()

            completion?()
        }
    }

    /// Check if SwiftECC has been preloaded
    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPreloaded
    }
}

#endif
