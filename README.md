# TandemKit

A LoopKit `PumpManager` for Tandem Mobi, building on
[pumpX2](https://github.com/jwoglom/pumpX2).


> There is NO WARRANTY IMPLIED OR EXPRESSED DUE TO USE OF THIS SOFTWARE.\
> YOU ASSUME ALL RISK FOR ANY MALFUNCTIONS, BUGS, OR INSULIN DELIVERY ACTIONS.\
> \
> TandemKit is NOT AFFILIATED WITH OR SUPPORTED by Tandem Diabetes or any other manufacturer.\
> **It has not been officially approved for use by any regulatory body and is provided as a RESEARCH TOOL ONLY.**

## Setup
### Trio

Trio links `TandemKit.framework` into the app and registers `TandemPumpManager`
in code. (`Sources/TandemKitPlugin` builds a Loop-style plugin bundle instead,
but nothing exercises that path today.)

1. Add TandemKit as a submodule at path `TandemKit`, tracking `dev`:

   ```bash
   git submodule add -b dev git@github.com:jwoglom/tandemkit TandemKit
   ```

   Add `TandemKit/TandemKit.xcodeproj` to `Trio.xcworkspace`.

2. In the `Trio` app target, link **and embed** `TandemKit.framework`.

3. In the same target, add the `ASN1` and `BigInt` packages under *Frameworks,
   Libraries, and Embedded Content* — see
   [Package products and the host app](#package-products-and-the-host-app).

4. Register the pump manager in `Trio/Sources/APS/DeviceDataManager.swift`:

   ```swift
   import TandemKit

   private let staticPumpManagers: [PumpManagerUI.Type] = [
       // ...
       TandemPumpManager.self
   ]

   private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
       // ...
       TandemPumpManager.pluginIdentifier: TandemPumpManager.self
   ]
   ```

5. Add a `.tandem` case to `PumpConfig.PumpType` in
   `Trio/Sources/Modules/PumpConfig/PumpConfigDataFlow.swift`. Its
   `pluginIdentifier` is `"TandemPumpManager"`, the string its LoopKit `Alert`s
   carry. Then handle the case in `PumpSetupView.swift`:

   ```swift
   case .tandem:
       setupViewController = TandemPumpManager.setupViewController(
           initialSettings: initialSettings,
           bluetoothProvider: bluetoothManager,
           colorPalette: .default,
           allowDebugFeatures: true,
           prefersToSkipUserInteraction: false,
           allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
       )
   ```

   Add the pump wherever Trio lists selectable pumps, e.g. `state.addPump(.tandem)`.


## Library details

### Dependencies

LoopKit is not a package dependency. The `TandemKit` target links
`LoopKit.framework` and `LoopKitUI.framework` out of `BUILT_PRODUCTS_DIR`, so
TandemKit cannot build on its own — another project in the same workspace has to
produce them. It must be the
[loopandlearn fork](https://github.com/loopandlearn/LoopKit) that Trio uses.
Upstream `LoopKit/LoopKit` has no `Pluggable`, which `TandemPumpManager`
conforms to.

Everything else comes from SwiftPM, resolved by `TandemKit.xcodeproj` and pinned
in its `Package.resolved`: `SwiftECC`, `BigInt`, `ASN1` and `Digest`.

`Package.swift` describes the source layout and resolves these, but cannot
compile the targets; see the comment at the top of the manifest. The Xcode
project is the supported build.

#### Package products and the host app

All four are automatic library products, so Xcode normally links them statically
into `TandemKit.framework` and the host app needs to do nothing.

That changes if a second framework in the workspace links one of the same
products. Xcode then rebuilds it as a generated dynamic framework
(`ASN1_<hash>_PackageProduct.framework`) so both clients share one copy. A
dynamic framework has to be embedded in the `.app`, and Xcode embeds only the
package products that the *application* target itself links. If the two
frameworks are the only ones linking it, nothing embeds it, and the app dies at
launch:

```
Library not loaded: @rpath/ASN1_<hash>_PackageProduct.framework/ASN1_<hash>_PackageProduct
Referenced from: .../Trio.app/Frameworks/AccuChekKit.framework/AccuChekKit
Termination Reason: DYLD 1 Library missing
```

Trio hits this, because `loopandlearn/AccuChekKit` links `leif-ibsen/ASN1` too.
The fix is step 3 in the Trio instructions above, and it is correct whether Xcode ends up building the
product statically or dynamically. Re-check it whenever the set of products
TandemKit links changes, or a new framework starts linking one of them.
