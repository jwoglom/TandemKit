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

### Host apps must embed the shared SwiftPM products

The `TandemKit` target links four remote SwiftPM products for the JPAKE path:
`SwiftECC`, `BigInt`, `ASN1` and `Digest`. All four are "automatic" library
products, so Xcode normally links them statically into `TandemKit.framework` and
the host app needs to do nothing.

That stops being true as soon as another framework in the same workspace links
one of the same products. Xcode then rebuilds that product as an auto-generated
dynamic framework -- `ASN1_<hash>_PackageProduct.framework` -- so the two
clients share one copy instead of each carrying duplicate symbols. A dynamic
framework has to be embedded in the `.app`, and Xcode only embeds package
products that the *application* target itself links. If only the two frameworks
link it, nothing embeds it and the app dies at launch, before any of its code
runs:

```
Library not loaded: @rpath/ASN1_<hash>_PackageProduct.framework/ASN1_<hash>_PackageProduct
Referenced from: .../Trio.app/Frameworks/AccuChekKit.framework/AccuChekKit
Termination Reason: DYLD 1 Library missing
```

Trio hits exactly this: `loopandlearn/AccuChekKit` links `leif-ibsen/ASN1` too,
and `ASN1` in turn depends on `BigInt`. The fix belongs in the host app, not
here -- add `ASN1` and `BigInt` to the **app** target's "Frameworks, Libraries,
and Embedded Content", the same way Trio already lists `SlideButton` and
`CryptoSwift`. Xcode embeds them from there whether it ends up building them
statically or dynamically, so the setting is correct either way.

Anything that changes which products TandemKit links, or that adds a framework
linking one of them, should be checked against this before it ships.

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

There is no exclusion list: every `.swift` file under `Tests/` must be a member
of `TandemKitTests`, and every directory under `Tests/` is discovered by the
script rather than registered by hand, so a new test file or a new test
directory cannot be silently left out of the CI run. A test that no longer
compiles has to be fixed or deleted. The same applies to `Sources/` — a
directory holding Swift files that no target claims fails the check too.

CI runs `--check` in every workflow, and `unit-tests.yml` additionally fails the
run if the test bundle executes zero tests, so "green" cannot mean "nothing
ran".

## Swift Package Manager

`Package.swift` describes the source layout but cannot currently compile it; see
the comment at the top of the manifest for why. Use the Xcode project.
