# TandemKit

TandemKit is a Swift library that provides communication utilities for Tandem insulin pumps.

## Building

TandemKit is a framework, not a standalone app, and it cannot be built on its
own: the `TandemKit` target links `LoopKit.framework` and `LoopKitUI.framework`
from `BUILT_PRODUCTS_DIR`, so some other project in the same Xcode workspace has
to produce them.

Normally that workspace is [Trio](https://github.com/nightscout/Trio)'s. Trio
pulls its dependencies in as git submodules -- TandemKit is one of them, as is
`loopandlearn/LoopKit` -- and `Trio.xcworkspace` contains both projects, so
opening Trio's workspace and building is all that is needed.

To build or test TandemKit by itself, check LoopKit out beside this repository
and put the two projects in a workspace together:

```
some-directory/
  LoopKit/          # git clone https://github.com/loopandlearn/LoopKit
  TandemKit/        # this repository
  Something.xcworkspace   # referencing LoopKit/LoopKit.xcodeproj and TandemKit/TandemKit.xcodeproj
```

Use the same LoopKit revision Trio's submodule points at. Upstream
`LoopKit/LoopKit` is not a drop-in substitute -- it has no `Pluggable`, which
`TandemPumpManager` conforms to.

`.github/workflows/unit-tests.yml` does exactly this and is the reference for
the setup: it checks out the pinned LoopKit, writes a two-project workspace, and
runs the `TandemKitTests` scheme against an iOS simulator.

## Tests

The unit tests live in `Tests/` and are built by the `TandemKitTests` target in
`TandemKit.xcodeproj`. Because the Xcode project compiles `Sources/TandemCore`,
`Sources/TandemKit` and `Sources/TandemKitUI` into a single `TandemKit`
framework, the tests `@testable import TandemKit` rather than the individual
source directories.

Test sources must be members of the `TandemKitTests` target to run at all. To
check for drift, or to add newly created files:

```bash
ruby scripts/check_xcodeproj_source_membership.rb --check
ruby scripts/check_xcodeproj_source_membership.rb --fix
```

Files deliberately left out of the target are listed, with a reason each, in
`EXCLUDED_TEST_PATHS` inside that script.

## Swift Package Manager

`Package.swift` describes the source layout but cannot currently compile it; see
the comment at the top of the manifest for why. Use the Xcode project.
