// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TandemKit",
    products: [
        .library(
            name: "TandemKit",
            targets: ["TandemKit"]
        ),
    ],
    targets: [
        .target(
            name: "TandemKit",
            path: "Sources/TandemKit"
        ),
        .testTarget(
            name: "TandemKitTests",
            dependencies: ["TandemKit"],
            path: "Tests/TandemKitTests"
        ),
    ]
)
