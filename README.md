# TandemKit

TandemKit is a Swift library that provides communication utilities for Tandem insulin pumps.

## Building

This project relies on Carthage for several dependencies (LoopKit, LoopKitUI, LoopTestingKit, MockKit, and MockKitUI). The binary frameworks are not committed to the repository. Before building the Xcode project you must fetch and build these frameworks.

1. Install [Carthage](https://github.com/Carthage/Carthage).
2. Run the following command from the repository root:
   
   ```bash
   ./carthage.sh update --platform iOS --use-xcframeworks
   ```

   This script mirrors the one used by OmniBLE and ensures the correct build settings for modern Xcode versions.
3. After Carthage finishes building, open `TandemKit.xcodeproj` and build the targets.

The generated frameworks will appear under `Carthage/Build/` and are referenced by the project via a `carthage copy-frameworks` build phase.
