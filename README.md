# TandemKit

TandemKit is a Swift library that provides communication utilities for Tandem insulin pumps.

## Building

This project relies on Carthage for several dependencies (LoopKit, LoopKitUI, LoopTestingKit, MockKit, and MockKitUI). The binary frameworks are not committed to the repository. Before building the Xcode project you must fetch and build these frameworks.

1. Install [Carthage](https://github.com/Carthage/Carthage).
2. Ensure your selected Xcode toolchain has the iOS 18.1 SDK installed (Xcode 16.1 or newer). LoopKit’s latest Interface Builder files target iOS 18.1, so Carthage will attempt to compile those nibs even when you only request macOS builds. If you use an older Xcode release you will see build failures such as `iOS 18.1 Platform Not Installed` while `carthage` archives the LoopKitUI target. Install the newer Xcode and, if you have multiple toolchains, point `xcode-select` (or `DEVELOPER_DIR`) at it before running Carthage. If you are already on Xcode 16.1 but still encounter that message, it usually means the optional “iOS 18.1” platform payload was never downloaded. Open **Xcode → Settings → Platforms**, install the iOS 18.1 SDK (or run `sudo xcodebuild -downloadPlatform iOS` from Terminal), and then rerun the bootstrap.
3. Run the following command from the repository root. Limiting the
   bootstrap to the LoopKit dependency avoids Carthage attempting to
   build SwiftECC, which does not vend a shared framework scheme (the
   project consumes SwiftECC through SwiftPM instead). **Do not run**
   `./carthage.sh bootstrap` without the `--use-xcframeworks` flag—the
   default flow attempts to create universal (`lipo`) frameworks that now
   contain identical arm64 slices for device and simulator builds, and
   Xcode will abort with the fatal error `have the same architectures and
   can't be in the same fat output file`.

   ```bash
   ./carthage.sh update LoopKit --platform iOS,macOS --use-xcframeworks
   ```

   This script mirrors the one used by OmniBLE and ensures the correct build settings for modern Xcode versions.
4. After Carthage finishes building, verify that `Carthage/Build/LoopKit.xcframework` and `Carthage/Build/LoopKitUI.xcframework` are present. The Swift Package manifest consumes these binaries on Apple platforms, while Linux continues to compile against the lightweight stubs.
5. If SwiftPM still reports `no such module 'LoopKit'` (or `LoopKitUI`) after running `swift build`/`swift run`, it means the binaries are missing or SwiftPM cached an earlier build before the xcframeworks were staged. Recheck that the two directories above exist, then clear the SwiftPM cache with `swift package reset` (or remove the `.build/` directory) before retrying. If the directories are absent entirely, delete `Carthage/Build/` and rerun the Carthage command—the log path printed at the end of the Carthage run points to any build failures that prevented the xcframeworks from being copied into place.
6. Open `TandemKit.xcodeproj` and build the targets.

The generated frameworks will appear under `Carthage/Build/` and are referenced by the project via a `carthage copy-frameworks` build phase.
