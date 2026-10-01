// swift-tools-version: 5.9
import PackageDescription

// NOTE: TandemKit.xcodeproj is the supported build. This manifest describes the
// source layout and resolves its dependencies, but SwiftPM cannot compile these
// targets as declared, for two reasons:
//
//   1. LoopKit is not vendored. Six TandemCore files import LoopKit, and
//      TandemKitUI/TandemKitPlugin import LoopKitUI; the repository ships
//      neither sources nor binaries for either -- the Xcode project links them
//      from BUILT_PRODUCTS_DIR, i.e. from the host app's workspace. Fixing this
//      means vendoring LoopKit back in, e.g. as binaryTargets, or building
//      it from a workspace the way TandemKit.xcodeproj does.
//   2. The module split below does not match the code. The Xcode project
//      compiles Sources/TandemCore, Sources/TandemKit and Sources/TandemKitUI
//      into a single TandemKit framework, and the sources rely on that -- for
//      example TandemCore/Common/Extensions/String.swift references
//      TandemKitUI's TandemKitHUDProvider.
//
// The unit tests are deliberately not declared here for the same reason: they
// `@testable import TandemKit` and expect that one module. They are built and
// run by the TandemKitTests target in TandemKit.xcodeproj; see
// .github/workflows/macos.yml.

// On Linux there is no Xcode project to fall back on, and Claude Code web
// sessions run in Linux containers (scripts/claude-web-setup.sh), so `swift
// build` is the only way for them to compile anything, and how
// .github/workflows/linux.yml tests the driver without a macOS runner.
//
// Sources/TandemCore and Sources/TandemKit compile into one module named
// TandemKit, matching TandemKit.xcodeproj and what the tests `@testable
// import`, against the shims in LinuxShims/ (see its README). TandemKitUI is
// SwiftUI and TandemKitPlugin depends on it, so neither builds here.
//
// SwiftECC and BigInt call SecRandomCopyBytes unconditionally and do not
// compile on Linux, so they are attached to Apple platforms only; swift-crypto
// stands in for CryptoKit hashing and the JPAKE provider becomes a trapping
// stub (SwiftECCJpakeProvider.swift).
#if os(Linux)
import Foundation

// Tests/TandemKitIntegrationTests needs a running faketandem and the TANDEMKIT_VIRTUAL_PUMP flag,
// without which it refuses to compile, so it is declared only when scripts/integration-test.sh (or
// CI's virtual pump build) asks for it with TANDEMKIT_INTEGRATION_TESTS=1. Fresh JPAKE pairing is
// compiled out here (SwiftECC does not build); everything else runs as on macOS.
let linuxIntegrationTests: [Target] = ProcessInfo.processInfo.environment["TANDEMKIT_INTEGRATION_TESTS"] == "1"
    ? [
        .testTarget(
            name: "TandemKitIntegrationTests",
            // TandemKitTests compiles the files the two Xcode test targets share; SwiftPM puts a
            // file in one target only.
            dependencies: ["TandemKit", "TandemKitTests", "CoreBluetooth", "LoopKit", "HealthKit"],
            path: "Tests/TandemKitIntegrationTests",
            exclude: ["Conformance/Oracles"]
        )
    ]
    : []

let package = Package(
    name: "TandemKit",
    products: [
        .library(name: "TandemKit", targets: ["TandemKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(name: "CoreBluetooth", path: "LinuxShims/CoreBluetooth"),
        .target(name: "HealthKit", path: "LinuxShims/HealthKit"),
        .target(name: "Combine", path: "LinuxShims/Combine"),
        .target(name: "LoopKit", dependencies: ["HealthKit"], path: "LinuxShims/LoopKit"),
        // Named TandemKit, not TandemCore: the Xcode project compiles
        // Sources/TandemCore, Sources/TandemKit and Sources/TandemKitUI into a
        // single TandemKit framework, and since b00b7bd every file in
        // Tests/TandemCoreTests does `@testable import TandemKit`. Only the
        // TandemCore sources build off-Apple, so on Linux the TandemKit module
        // is that subset.
        .target(
            name: "TandemKit",
            dependencies: [
                "LoopKit",
                "CoreBluetooth",
                "HealthKit",
                "Combine",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources",
            exclude: ["TandemKit/Info.plist"],
            sources: ["TandemCore", "TandemKit"]
        ),
        .testTarget(
            name: "TandemCoreTests",
            dependencies: ["TandemKit", "CoreBluetooth"],
            path: "Tests/TandemCoreTests"
        ),
        // TandemKitUI view-model tests; macOS-only, still run via the Xcode
        // project. A new one must be added here or the Linux build breaks.
        .testTarget(
            name: "TandemKitTests",
            dependencies: ["TandemKit", "CoreBluetooth", "LoopKit", "HealthKit"],
            // The dose oracles live with the conformance tests but are members of both Xcode test
            // targets; DoseOracleTests and MockPumpManagerDelegate use them.
            path: "Tests",
            exclude: [
                "TandemKitTests/TandemKitFillTubingViewModelTests.swift",
                "TandemKitTests/TandemFeatureFlagsTests.swift",
                "TandemKitTests/TandemKitChangeCartridgeViewModelTests.swift",
                "TandemKitTests/TandemKitFillCannulaViewModelTests.swift",
                "TandemKitTests/TandemKitControlIQSettingsViewModelTests.swift",
                "TandemKitTests/TandemKitNotificationsViewModelTests.swift",
                "TandemKitTests/TandemKitScanViewModelTests.swift"
            ],
            sources: ["TandemKitTests", "TandemKitIntegrationTests/Conformance/Oracles"]
        )
    ] + linuxIntegrationTests
)

#else

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
        ),
        .library(
            name: "TandemKit",
            targets: ["TandemKit"]
        ),
        .library(
            name: "TandemKitUI",
            targets: ["TandemKitUI"]
        ),
        .library(
            name: "TandemKitPlugin",
            targets: ["TandemKitPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "5.5.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TandemCore",
            dependencies: [
                .product(name: "SwiftECC", package: "SwiftECC"),
                .product(name: "BigInt", package: "BigInt")
            ],
            path: "Sources/TandemCore"
        ),
        .target(
            name: "TandemKit",
            dependencies: ["TandemCore"],
            path: "Sources/TandemKit"
        ),
        .target(
            name: "TandemKitUI",
            dependencies: ["TandemKit", "TandemCore"],
            path: "Sources/TandemKitUI"
        ),
        .target(
            name: "TandemKitPlugin",
            dependencies: ["TandemKit", "TandemCore"],
            path: "Sources/TandemKitPlugin"
        )
    ]
)

#endif
