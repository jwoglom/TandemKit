// swift-tools-version: 5.9
import PackageDescription

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
            name: "TandemBLE",
            targets: ["TandemBLE"]
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
            name: "tandemkit-cli",
            targets: ["TandemCLI"]
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
    targets: {
        var targets: [Target] = [
            // Optional: Mbed TLS headers and shim are only built when the underlying library is
            // available in the build environment. See the README for the linker flags needed to
            // provide vendored sources or prebuilt binaries to SwiftPM.
            .target(
                name: "MbedTLS",
                path: "Sources/MbedTLS",
                publicHeadersPath: "include"
            ),
            .target(
                name: "MbedTLSShim",
                dependencies: ["MbedTLS"],
                path: "Sources/MbedTLSShim",
                publicHeadersPath: "include"
            ),
            .target(
                name: "Bluetooth",
                path: "Sources/Bluetooth"
            ),
            .target(
                name: "CoreBluetooth",
                dependencies: [
                    .target(name: "Bluetooth", condition: .when(platforms: [.linux]))
                ],
                path: "Sources/CoreBluetooth"
            ),
            .target(
                name: "TandemCore",
                dependencies: [
                    .product(name: "SwiftECC", package: "SwiftECC"),
                    .product(name: "BigInt", package: "BigInt"),
                    .product(name: "Logging", package: "swift-log"),
                    .target(name: "CoreBluetooth", condition: .when(platforms: [.linux]))
                    // Add "MbedTLSShim" here when providing Mbed TLS headers and binaries to SwiftPM.
                ],
                path: "Sources/TandemCore"
            ),
            .target(
                name: "TandemBLE",
                dependencies: [
                    "TandemCore",
                    "LoopKit",
                    .target(name: "Bluetooth", condition: .when(platforms: [.linux])),
                    .target(name: "CoreBluetooth", condition: .when(platforms: [.linux]))
                ],
                path: "Sources/TandemBLE"
            ),
            .target(
                name: "TandemKit",
                dependencies: ["TandemCore", "TandemBLE", "LoopKit"],
                path: "Sources/TandemKit"
            ),
            .target(
                name: "TandemKitUI",
                dependencies: ["TandemKit", "TandemCore", "LoopKitUI"],
                path: "Sources/TandemKitUI"
            ),
            .target(
                name: "TandemKitPlugin",
                dependencies: ["TandemKit", "LoopKitUI", "TandemCore"],
                path: "Sources/TandemKitPlugin"
            ),
            .executableTarget(
                name: "TandemCLI",
                dependencies: [
                    "TandemCore",
                    "TandemBLE",
                    "TandemKit"
                ],
                path: "Sources/TandemCLI",
                swiftSettings: [
                    .unsafeFlags(["-parse-as-library"])
                ]
            ),
            .executableTarget(
                name: "TandemSimulator",
                dependencies: [
                    "TandemCore",
                    "TandemBLE",
                    .product(name: "SwiftECC", package: "SwiftECC"),
                    .product(name: "BigInt", package: "BigInt"),
                    .product(name: "Logging", package: "swift-log"),
                    .target(name: "CoreBluetooth", condition: .when(platforms: [.linux]))
                ],
                path: "Sources/TandemSimulator",
                resources: [
                    .copy("README.md")
                ],
                swiftSettings: [
                    .unsafeFlags(["-parse-as-library"])
                ]
            ),
            .testTarget(
                name: "TandemCoreTests",
                dependencies: ["TandemCore"],
                path: "Tests/TandemCoreTests"
            ),
            .testTarget(
                name: "TandemKitTests",
                dependencies: ["TandemKit", "TandemCore", "TandemBLE"],
                path: "Tests/TandemKitTests"
            ),
            .testTarget(
                name: "TandemCommTests",
                dependencies: ["TandemKit", "TandemCore"],
                path: "Tests/TandemCommTests"
            ),
            .testTarget(
                name: "TandemSimulatorTests",
                dependencies: ["TandemSimulator", "TandemCore", "TandemBLE"],
                path: "Tests/TandemSimulatorTests"
            )
        ]

        // Always use source-based shims since the binary frameworks don't support macOS
        targets.append(contentsOf: [
            .target(
                name: "LoopKit",
                path: "Sources/LoopKit"
            ),
            .target(
                name: "LoopKitUI",
                dependencies: ["LoopKit"],
                path: "Sources/LoopKitUI"
            )
        ])

        return targets
    }()
)
