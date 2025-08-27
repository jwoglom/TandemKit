// swift-tools-version: 6.0
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
    targets: [
        .target(
            name: "TandemCore",
            path: "Sources/TandemCore"
        ),
        .target(
            name: "TandemBLE",
            dependencies: ["TandemCore"],
            path: "Sources/TandemBLE"
        ),
        .target(
            name: "TandemKit",
            dependencies: ["TandemCore", "TandemBLE"],
            path: "Sources/TandemKit"
        ),
        .testTarget(
            name: "TandemCoreTests",
            dependencies: ["TandemCore"],
            path: "Tests/TandemCoreTests"
        ),
    ]
)
