# TandemKit

TandemKit is a Swift library that provides communication utilities for Tandem insulin pumps.

## Building

This project relies on Carthage for several dependencies (LoopKit, LoopKitUI, LoopTestingKit, MockKit, and MockKitUI). The binary frameworks are not committed to the repository. Before building the Xcode project you must fetch and build these frameworks.

1. Install [Carthage](https://github.com/Carthage/Carthage).
2. Run the following command from the repository root:

   ```bash
   ./carthage.sh update --platform iOS,macOS --use-xcframeworks
   ```

   This script mirrors the one used by OmniBLE and ensures the correct build settings for modern Xcode versions.
3. After Carthage finishes building, verify that `Carthage/Build/LoopKit.xcframework` and `Carthage/Build/LoopKitUI.xcframework` are present. The Swift Package manifest consumes these binaries on Apple platforms, while Linux continues to compile against the lightweight stubs.
4. Open `TandemKit.xcodeproj` and build the targets.

The generated frameworks will appear under `Carthage/Build/` and are referenced by the project via a `carthage copy-frameworks` build phase.

### Optional Mbed TLS builds

When an Mbed TLS toolchain becomes available, the package exposes two SwiftPM targets—`MbedTLS` (a module map for the upstream headers) and `MbedTLSShim` (a thin C wrapper used by `JpakeAuthBuilder`). To enable the shim in your build:

1. Provide the Mbed TLS headers and binaries via either a local install or a vendor drop under `Sources/MbedTLS`.
2. Add `MbedTLSShim` as a dependency of the `TandemCore` target inside `Package.swift` so Swift can import the module when `#if canImport(MbedTLS)` evaluates to `true`.
3. Pass the include/library search paths and linker flags when building, for example:

   ```bash
   swift build \
     -Xcc -I/path/to/mbedtls/include \
     -Xlinker -L/path/to/mbedtls/lib \
     -Xlinker -lmbedtls -Xlinker -lmbedcrypto
   ```

The Mbed TLS-specific code is fully gated by `#if canImport(MbedTLS)` so Apple and Linux builds continue to compile without the external dependency present.
