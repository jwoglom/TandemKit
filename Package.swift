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
// run by the TandemKitTests target in TandemKit.xcodeproj; see the
// tandemkit-tests job in .github/workflows/integration.yml.

// On Linux there is no Xcode project to fall back on, and Claude Code web
// sessions run in Linux containers (scripts/claude-web-setup.sh), so `swift
// build` is the only way for them to compile anything. Declare the subset that
// can actually be built there: TandemCore, against source shims for LoopKit and
// CoreBluetooth kept outside Sources/ (see LinuxShims/README.md). SwiftECC and
// BigInt call SecRandomCopyBytes unconditionally and do not compile on Linux,
// so they are attached to Apple platforms only; swift-crypto stands in for
// CryptoKit hashing and the JPAKE provider becomes a trapping stub
// (SwiftECCJpakeProvider.swift). TandemKit/TandemKitUI/TandemKitPlugin import
// UIKit/SwiftUI/HealthKit/LoopKitUI and are not declared here.
#if os(Linux)

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
        .target(name: "LoopKit", path: "LinuxShims/LoopKit"),
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
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/TandemCore"
        ),
        .testTarget(
            name: "TandemCoreTests",
            dependencies: ["TandemKit", "CoreBluetooth"],
            path: "Tests/TandemCoreTests"
        )
        // Tests/TandemKitTests is not declared: it drives TandemPumpManager and
        // the rest of the iOS-only layer. It is built and run on macOS by the
        // tandemkit-tests job in .github/workflows/integration.yml.
    ]
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
