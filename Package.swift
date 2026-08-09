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
// .github/workflows/unit-tests.yml.

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
        ),
        .executable(
            name: "tandem-simulator",
            targets: ["TandemSimulator"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "5.5.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3")
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
        ),
        .executableTarget(
            name: "TandemSimulator",
            dependencies: [
                "TandemCore",
                .product(name: "SwiftECC", package: "SwiftECC"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/TandemSimulator",
            resources: [
                .copy("README.md")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
