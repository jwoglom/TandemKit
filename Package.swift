// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TandemKit",
    platforms: [
        .macOS(.v10_15),
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
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "3.0.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
    ],
    targets: {
        var targets: [Target] = [
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
                    .product(name: "Logging", package: "swift-log")
                ],
                path: "Sources/TandemSimulator",
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
                name: "TandemSimulatorTests",
                dependencies: ["TandemSimulator", "TandemCore", "TandemBLE"],
                path: "Tests/TandemSimulatorTests"
            ),
        ]

        #if os(Linux)
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
        #else
        targets.append(contentsOf: [
            .binaryTarget(
                name: "LoopKitBinary",
                path: "Carthage/Build/LoopKit.xcframework"
            ),
            .binaryTarget(
                name: "LoopKitUIBinary",
                path: "Carthage/Build/LoopKitUI.xcframework"
            ),
            .target(
                name: "LoopKit",
                dependencies: [
                    .target(name: "LoopKitBinary")
                ],
                path: "Sources/LoopKit"
            ),
            .target(
                name: "LoopKitUI",
                dependencies: [
                    "LoopKit",
                    .target(name: "LoopKitUIBinary")
                ],
                path: "Sources/LoopKitUI"
            )
        ])
        #endif

        return targets
    }()
)
