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
    ],
    dependencies: [
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "3.0.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.0.0"),
    ],
    targets: [
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
            name: "LoopKit",
            path: "Sources/LoopKit"
        ),
        .target(
            name: "LoopKitUI",
            dependencies: ["LoopKit"],
            path: "Sources/LoopKitUI"
        ),
        .target(
            name: "TandemCore",
            dependencies: [
                .product(name: "SwiftECC", package: "SwiftECC"),
                .product(name: "BigInt", package: "BigInt"),
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
                "TandemBLE"
            ],
            path: "Sources/TandemCLI",
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
    ]
)
