// swift-tools-version: 5.9
import PackageDescription

// -----------------------------------------------------------------------------
// Why this manifest was rewritten
//
// The previous manifest referenced 7 target directories that had been deleted in
// the "cleanup libs"/"cleanup project structure" refactors (MbedTLS, MbedTLSShim,
// Bluetooth, CoreBluetooth, TandemBLE, LoopKit, LoopKitUI). SwiftPM failed at
// manifest load on EVERY platform as a result (`invalid custom path
// 'Sources/MbedTLS'`), so `swift build`/`swift test` were impossible.
//
// This manifest instead describes what SwiftPM can actually build today: the
// platform-agnostic `TandemCore` library plus the small Linux-only shims it needs
// to compile off-Apple. The iOS app is built by TandemKit.xcodeproj, which does
// NOT read this file (see below), so trimming the manifest to buildable targets
// has no effect on the Apple build.
//
// The Linux shims (LoopKit/CoreBluetooth/Bluetooth) live under the top-level
// `LinuxShims/` directory — a sibling of `Sources/` — so the iOS source tree in
// `Sources/` is never polluted with non-iOS code. See LinuxShims/README.md.
// -----------------------------------------------------------------------------
// SwiftPM manifest scope
//
// The Apple/iOS build of this repository is produced exclusively by
// TandemKit.xcodeproj (consumed by the Trio app as a subproject). That project
// carries its own SwiftPM package references (SwiftECC, BigInt, ASN1, Digest)
// and links LoopKit/LoopKitUI as Carthage xcframeworks — it does NOT read this
// Package.swift. Editing this manifest therefore cannot affect the Apple build.
//
// This manifest exists so the platform-agnostic protocol/message layer
// (`TandemCore`) can be built and unit-tested with plain `swift build` /
// `swift test`, including on Linux (used by CI/tooling to prewarm caches and to
// exercise the message catalog).
//
// The iOS integration layer (`TandemKit`, `TandemKitUI`, `TandemKitPlugin`) and
// the historical `TandemBLE` module are intentionally NOT declared here: they
// depend on UIKit / HealthKit / AVFoundation / Combine / SwiftUI (and, for
// TandemBLE, on BLE types that were removed from the tree in the "cleanup
// project structure" refactor), none of which are available to a desktop
// SwiftPM toolchain on either macOS or Linux. They are built for iOS through
// the Xcode project.
//
// On Apple SwiftPM platforms SwiftECC/BigInt supply the real JPAKE/ECC crypto.
// Those packages do not compile on Linux (unconditional SecRandomCopyBytes), so
// they are attached only via `.when(platforms:)` for Apple platforms, keeping
// them out of the Linux build graph. On Linux, CryptoKit hashing is provided by
// swift-crypto, and the JPAKE provider is replaced by an honest stub that traps
// if invoked (see SwiftECCJpakeProvider.swift).
// -----------------------------------------------------------------------------

let applePlatforms: [Platform] = [.iOS, .macOS, .macCatalyst, .tvOS, .watchOS]

let package = Package(
    name: "TandemKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "TandemCore",
            targets: ["TandemCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "5.5.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        // Linux-only shims, kept under LinuxShims/ (outside Sources/) so the iOS
        // source tree carries no non-iOS code. On Apple platforms
        // `import CoreBluetooth` resolves to the system framework, so these
        // targets are attached to TandemCore only via `.when(platforms: [.linux])`
        // and are never built on Apple.
        .target(
            name: "Bluetooth",
            path: "LinuxShims/Bluetooth"
        ),
        .target(
            name: "CoreBluetooth",
            dependencies: [
                .target(name: "Bluetooth", condition: .when(platforms: [.linux]))
            ],
            path: "LinuxShims/CoreBluetooth"
        ),
        // Source-based LoopKit shim. The real LoopKit is only available on Apple
        // (as a Carthage xcframework via the Xcode project); this shim lets
        // TandemCore compile against the LoopKit surface it uses on any SwiftPM
        // platform.
        .target(
            name: "LoopKit",
            path: "LinuxShims/LoopKit"
        ),
        .target(
            name: "TandemCore",
            dependencies: [
                "LoopKit",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftECC", package: "SwiftECC", condition: .when(platforms: applePlatforms)),
                .product(name: "BigInt", package: "BigInt", condition: .when(platforms: applePlatforms)),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
                .target(name: "CoreBluetooth", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/TandemCore"
        ),
        .testTarget(
            name: "TandemCoreTests",
            dependencies: [
                "TandemCore",
                .target(name: "CoreBluetooth", condition: .when(platforms: [.linux]))
            ],
            path: "Tests/TandemCoreTests",
            // These fixtures predate the "cleanup project structure" refactor and
            // reference symbols that no longer exist in TandemCore
            // (PumpChallengeRequestBuilder, PumpStateSupplier) or APIs that have
            // since changed shape (IDPManager initializers, QualifyingEvent's
            // now-private `fromBitmask` / removed `suggestedHandlers`). Because the
            // SwiftPM manifest never loaded before this change, they have never
            // compiled and are not part of the Xcode test target. They cannot be
            // gated with XCTSkip (the references don't resolve), so they are
            // excluded here and left for a follow-up that realigns them with the
            // current API.
            exclude: [
                "PumpChallengeRequestBuilderTests.swift",
                "PumpStateSupplierTests.swift",
                "Builders/IDPManagerTests.swift",
                "Messages/QualifyingEvent/QualifyingEventTests.swift"
            ]
        )
        // NOTE: TandemCommTests and TandemKitTests are intentionally not declared
        // here — both `@testable import TandemKit`, and TandemKit is part of the
        // iOS-only integration layer that is not built by desktop SwiftPM (see the
        // header note above). They run via the Xcode project.
    ]
)
