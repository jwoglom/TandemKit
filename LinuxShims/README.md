# LinuxShims

Linux-only SwiftPM stubs for `LoopKit`, `CoreBluetooth`, and `Bluetooth`.

They exist solely so `TandemCore` can compile and be unit-tested with plain
`swift build`/`swift test` on non-Apple platforms. They are attached to
`TandemCore` only via `.when(platforms: [.linux])` in `Package.swift` and are
**never** compiled into the iOS/Xcode build (TandemKit.xcodeproj), which links
the real LoopKit xcframeworks and the system CoreBluetooth framework.
