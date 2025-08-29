// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TandemKit",
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
    ],
    dependencies: [
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
            name: "TandemCore",
            dependencies: [
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
        .testTarget(
            name: "TandemCoreTests",
            dependencies: ["TandemCore"],
            path: "Tests/TandemCoreTests"
        ),
    ]
)
