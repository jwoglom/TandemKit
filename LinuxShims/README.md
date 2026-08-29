# LinuxShims

Linux-only SwiftPM stand-ins for the Apple frameworks TandemKit builds against:
`LoopKit`, `HealthKit`, `CoreBluetooth` and `Combine`.

They exist so `Sources/TandemCore` and `Sources/TandemKit` can compile and be
unit-tested with plain `swift build` / `swift test` on non-Apple platforms —
which is how CI covers the driver without paying for a macOS runner. They are
declared as targets only in the `#if os(Linux)` branch of `Package.swift` and
are **never** compiled into the iOS/Xcode build (TandemKit.xcodeproj), which
links the real LoopKit frameworks and the system Apple frameworks.

## What they are, and are not

These are fakes. Code that compiles against them has **not** been proven to
compile against the real frameworks, so the macOS job in CI remains the only
check of genuine LoopKit conformance. Keep that job.

To limit the drift, the LoopKit shim is written against the real source at the
revision Trio pins (`loopandlearn/LoopKit`, see the `LOOPKIT_REVISION` in the
macOS workflow). When a signature is uncertain, check it there rather than
guessing — several members in this shim were once invented and silently wrong
(a `static localizedTitle`, a `dosingDecisionDelegate` property, a
`pumpManagerRecommendsLoop` delegate callback), and a synchronous `notify` on
`WeakSynchronizedDelegate` deadlocked the driver the first time real tests ran
against it. The weak collections here are direct ports for that reason.

## Adding to a shim

Add only what the code actually needs, and match the real declaration exactly —
including mutating-ness, failability, argument labels and dispatch semantics. A
shim that is *more permissive* than the real framework lets broken code pass on
Linux and fail in Xcode, which is the failure mode this directory has to avoid.

## The `canImport` hazard

Naming a shim target after an Apple framework flips every `#if canImport(...)`
for that name to true on Linux. That is why there is no `UIKit` shim: adding one
turned on a `canImport(UIKit)` branch inside the LoopKit shim that referenced
`UIViewController`. Where a framework is needed in only one or two places,
guard the import at the use site instead of creating a module for it.
