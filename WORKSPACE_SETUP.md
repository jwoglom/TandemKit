# TandemKit Workspace Setup

This document explains how to use TandemKit in a workspace setup, similar to how it's used in Trio and other Loop-based projects.

## Overview

TandemKit can be used in two ways:

1. **Standalone Development**: Clone TandemKit by itself, and it will use local stub implementations of LoopKit for development
2. **Workspace Development**: Clone TandemKit alongside LoopKit and other dependencies (like in Trio), and it will use the real LoopKit framework

## Workspace Setup

### Directory Structure

When used in a workspace (like Trio), the directory structure should look like:

```
workspace-root/
├── TandemKit/
├── LoopKit/
├── OmniKit/
├── ... (other dependencies)
```

### Automatic Configuration in CI

The GitHub Actions CI workflows automatically detect when TandemKit is checked out alongside LoopKit and use the workspace configuration:

1. Both `TandemKit` and `LoopKit` repositories are checked out as siblings
2. `Package.local.swift` is copied to `Package.swift` to use local path dependencies
3. `Cartfile.local` is processed to use local LoopKit for Carthage builds

### Manual Workspace Setup

To manually set up TandemKit for workspace development:

1. Clone the repositories:
   ```bash
   mkdir workspace && cd workspace
   git clone https://github.com/your-org/TandemKit.git
   git clone --branch loop-release/v2.x https://github.com/LoopKit/LoopKit.git
   ```

2. Configure TandemKit to use local LoopKit:
   ```bash
   cd TandemKit
   cp Package.local.swift Package.swift
   ```

3. Build with SPM:
   ```bash
   swift build
   ```

   Or with Carthage:
   ```bash
   # Update Cartfile to use local LoopKit
   export PWD=$(pwd)
   sed "s|\${PWD}|$PWD|g" Cartfile.local > Cartfile
   ./carthage.sh bootstrap --platform iOS
   ```

### Integration with Trio

When TandemKit is used as a submodule in Trio:

1. Trio's `.gitmodules` should include both TandemKit and LoopKit
2. The workspace will automatically use local dependencies since both are checked out
3. No additional configuration is needed - Xcode workspace handles the dependency resolution

## Configuration Files

### Package.swift (Default)

The default `Package.swift` uses local stub implementations of LoopKit. This allows:
- Standalone development without needing the full LoopKit
- Building on platforms not supported by LoopKit's xcframeworks (like macOS for testing)
- Quick iteration without workspace setup

### Package.local.swift (Workspace)

The workspace version `Package.local.swift` uses:
- `.package(path: "../LoopKit")` to reference the local LoopKit repository
- Real LoopKit products instead of stubs

### Cartfile (Default)

The default `Cartfile` fetches dependencies from GitHub:
- `github "LoopKit/LoopKit" "loop-release/v2.x"`
- `github "leif-ibsen/SwiftECC" ~> 5.5.0`

### Cartfile.local (Workspace)

The workspace `Cartfile.local` uses local paths:
- `git "file://${PWD}/../LoopKit" "loop-release/v2.x"`

## Benefits of Workspace Setup

1. **Consistent Dependencies**: All projects in the workspace share the same LoopKit version
2. **Cross-Project Development**: Changes to LoopKit are immediately available to TandemKit
3. **CI Integration**: GitHub Actions can test TandemKit with the exact LoopKit version used in production
4. **Submodule Support**: Works seamlessly with git submodules used by Trio

## Troubleshooting

### Package Resolution Errors

If you see errors about missing LoopKit package:
- Ensure LoopKit is checked out at `../LoopKit` relative to TandemKit
- Verify you're using `Package.local.swift` (copy it to `Package.swift`)

### Carthage Build Errors

If Carthage can't find local dependencies:
- Ensure the `Cartfile` uses absolute paths with `file://` protocol
- Try using `file://$(pwd)/../LoopKit` instead of relative paths

### Xcode Workspace Issues

If Xcode doesn't find dependencies:
- Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Re-resolve package dependencies in Xcode: File → Packages → Reset Package Caches
