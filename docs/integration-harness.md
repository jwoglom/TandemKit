# Integration harness: TandemKit against faketandem

`TandemKitIntegrationTests` drives the real driver stack — `TandemPumpManager`,
`TandemBluetoothManager`, `TandemPeripheralManager`, JPAKE, message signing,
packetization — against [faketandem](https://github.com/jwoglom/faketandem), the Go
Tandem pump emulator, over its virtual GATT link. Nothing on the driver side is stubbed;
the only substitution is CoreBluetooth itself. The target is built with
`VirtualPump.xcconfig` (`TANDEMKIT_VIRTUAL_PUMP`), under which
`Sources/TandemKit/PumpManager/VirtualPump/` supplies its own `CBCentralManager`,
`CBPeripheral`, `CBService` and `CBCharacteristic`, carried over a socket. They shadow
CoreBluetooth's inside the module, so the driver code is exactly what ships; without the
flag none of it compiles, and the target refuses to build.

The unit tests in `TandemKitTests` stay as they are: fast, hermetic, `StubPumpBluetooth`.
This target is for the questions those cannot answer — does the driver actually
authenticate, reassemble, sign, poll and report against a pump that behaves like a pump.

## Running

Prerequisites: Xcode with an iOS simulator, Trio simulator products for the staged
LoopKit (see `scripts/test-local.sh`), Go, Java 17+ (pumpX2's cliparser), and a
faketandem checkout with its cliparser jar (`make jar` there).

```bash
# from the TandemKit checkout
FAKETANDEM_DIR=../faketandem scripts/integration-test.sh            # build + run everything
FAKETANDEM_DIR=../faketandem scripts/integration-test.sh test \
    -only-testing:TandemKitIntegrationTests/BolusIntegrationTests    # one class, no rebuild
scripts/integration-test.sh build                                  # compile only, no emulator
```

On Linux the same script runs the suite under `swift test` instead, built with
`-DTANDEMKIT_VIRTUAL_PUMP` into `.build-virtual`; Package.swift declares the target only when
`TANDEMKIT_INTEGRATION_TESTS=1`, which the script sets. It needs Go, Java and faketandem but no
simulator. Filter with `--filter`, e.g. `scripts/integration-test.sh test --filter
TandemKitIntegrationTests.BolusIntegrationTests`. Differences from macOS:

- Fresh JPAKE pairing (`PairingIntegrationTests`) is compiled out, since SwiftECC does not build
  and the JPAKE provider is a trapping stub; the rest pair with a seeded long-term key as on macOS.
- swift-corelibs-xctest has no `XCTExpectFailure` or `XCTAttachment`.
  `LinuxExpectedFailure.swift` supplies a strict `XCTExpectFailure`, and each test's request log
  is written to `LOG_DIR/request-logs/` instead of being attached. The stand-in carries on past an
  expected failure where Apple's XCTest stops under `continueAfterFailure = false`, so a class with
  expected failures sets it to `true`; otherwise macOS silently skips what follows them.
- Foundation's `URLSessionWebSocketTask` needs a libcurl built with WebSocket support, which the
  toolchain's is not, so the control socket uses `LinuxWebSocket.swift`, a plain ws:// client.

The script builds faketandem from `FAKETANDEM_DIR`, starts it with `-transport virtual`
on two free loopback ports, waits for its API, runs the `TandemKitIntegrationTests`
scheme through `scripts/test-local.sh`, and kills the emulator on exit. Logs:

| File (under `LOG_DIR`, default `.derived-data-virtual-pump/integration-logs/`) | Contents |
| --- | --- |
| `faketandem.log` | The emulator's log: every fragment received and sent, every handler decision. |
| `xcodebuild.log` | The driver's `TandemLogger` output and the XCTest results. |
| `TandemKitIntegrationTests.xcresult` | The result bundle; each test attaches the pump's request log (`xcrun xcresulttool export attachments --path … --output-path …`). |

The script's header lists the environment variables it reads.

CI runs it from `.github/workflows/macos.yml` (the `integration` job, only the classes
`MACOS_SUITES` names: those that need Apple's frameworks, such as `PairingIntegrationTests`, whose
fresh JPAKE pairing needs SwiftECC) and from `.github/workflows/linux.yml` (every class, in shards: a
new class runs in the `integration` shard unless `FAULT_SUITES`, `COMMAND_SUITES` or
`HISTORY_SUITES` names it). A class that tests something only Apple's frameworks show goes on the
macOS list. Both fail if any integration test skips, because a skip means the emulator's addresses
never reached the test process. faketandem comes from its default branch; `faketandem_ref` on a
manual run picks another, and a pull request uses a faketandem branch of the same name when one
exists. What CI skips (documentation-only changes, superseded commits, a tree that already passed)
is in each workflow's `plan` job (`scripts/ci/plan.sh`), its `concurrency` and `cancel-on-close.yml`.

### How the tests find the emulator

The test bundle runs inside the iOS simulator under `xctest`. It cannot spawn processes
(`Process` does not exist in the iOS SDK), so the emulator is started outside and its
addresses are passed in through the environment. xcodebuild forwards any variable named
`TEST_RUNNER_<NAME>` to the test process as `<NAME>`; the simulator shares the host's
network namespace, so loopback addresses work.

| In the test process | Passed to xcodebuild as | Meaning |
| --- | --- | --- |
| `FAKETANDEM_GATT` | `TEST_RUNNER_FAKETANDEM_GATT` | `host:port` of the virtual GATT link (`-virtual-addr`). |
| `FAKETANDEM_API_URL` | `TEST_RUNNER_FAKETANDEM_API_URL` | Base URL of the HTTP/websocket API (`-api-addr`). |

Without both variables every test throws `XCTSkip`, so the scheme is safe to run anywhere;
it simply reports skips.

## Architecture

```
 XCTest (iOS simulator, xctest process)                     faketandem (Go, host process)
 ┌────────────────────────────────────────────┐             ┌──────────────────────────────────┐
 │ *IntegrationTests                          │             │                                  │
 │   └ FaketandemIntegrationTestCase          │             │  pkg/api + pkg/harness           │
 │       ├ FaketandemHarness ─────────────────┼── HTTP ────▶│   /api/state /api/clock          │
 │       │   ├ FaketandemClient (HTTP)        │             │   /api/log   /api/faults         │
 │       │   └ FaketandemControlSocket (ws) ──┼── ws ──────▶│   /ws: setPairingCode,           │
 │       │                                    │             │       setLongTermKey, disconnect │
 │       └ Driver                             │             │                                  │
 │           ├ MockPumpManagerDelegate        │             │  pkg/handler Router              │
 │           ├ TandemPumpManager (ManualClock)│             │   JPAKE, signing, handlers,      │
 │           ├ TandemBluetoothManager         │             │   pkg/state simulator            │
 │           │   └ TandemPeripheralManager    │             │                                  │
 │           └ virtual CBCentralManager/  ────┼── TCP ─────▶│  pkg/bluetooth VirtualTransport  │
 │             CBPeripheral (VirtualPump/)    │             │                                  │
 │             (newline JSON, GATT semantics) │             │   hello/attach/write/notify      │
 └────────────────────────────────────────────┘             └──────────────────────────────────┘
```

- `FaketandemHarness` reads the environment, holds the clients, resets the emulator
  before each test (`reset()`: drop any attached central, set the pairing code and clear
  the long-term key, real clock, no faults, `PairStep2`, empty request log), builds a
  `Driver`, and offers the flows the onboarding UI uses (`discover`, `pair`, `sync`).
- The virtual `CBCentralManager` reports a link faketandem drops as CoreBluetooth would: a
  `disconnect` with reason `radio_off` (the `radioOff` fault), or a socket that closes with no
  `disconnect` at all, as `CBError.connectionTimeout`, the phone losing the pump; any other reason as
  `peripheralDisconnected`, the pump ending the link.
- `Driver` is one real stack: `VirtualPump.endpoint` pointed at the emulator, then
  `TandemBluetoothManager()` (which creates its `CBCentralManager` as in production) →
  `TandemPumpManager(state:bluetooth:clock:)` with a `MockPumpManagerDelegate` attached in
  Trio's order (delegate, then queue). The clock is a `ManualClock` started at "now", so a
  test can move the driver's idea of time (bolus estimated end, sync throttles) without
  waiting; the emulator stays on its own clock unless a test drives `/api/clock`.
- `FaketandemClient` is the HTTP surface: pairing state, `/api/state` snapshot and direct
  writes, `/api/clock`, the history feed (`history(since:)`, paging `GET /api/history` to
  the end), pump-initiated actions (bolus, temp basal, suspend/resume, history, qualifying
  events), the request log, faults, the link's ATT MTU (`transport()` / `setATTMTU(_:)`),
  and the legacy settings table.
- `FaketandemControlSocket` is the websocket surface for what only exists as websocket
  commands: pairing code, long-term key, pump-side disconnect, and the pairing status with
  the key bytes. One socket is shared for the whole test process; the emulator accepts
  several, but one is all the tests need.
- `IntegrationWait` polls a condition while pumping the run loop; `ResultBox` carries a
  completion result to a polling wait. Neither blocks the main thread outright, because
  parts of the driver complete on the main queue.

### Pump time is local time

A Tandem pump holds a **date and time with no zone attached**: its pump-epoch seconds count
from 2008-01-01 00:00:00 as read on the pump's own clock, and every consumer decodes them as
local time — TandemKit's `Dates.fromJan12008ToUnixEpochSeconds` subtracts
`TimeZone.current.secondsFromGMT()`. The pump only changes its clock when someone sets it, on
the pump or with `ChangeTimeDateRequest`; it does not follow DST or a trip. The emulator
encodes the same way, so two separate offsets sit between its clock and the wire and they mean
different things:

| `/api/clock` field | Meaning |
| --- | --- |
| `pump_timezone` | The IANA zone whose local time the pump's clock was last set to. Naming it in a `PUT` sets the clock to that zone's local time at that moment; the offset is then fixed. A `PUT` that leaves it out does not move the clock. `UTC` turns the convention off. |
| `pump_timezone_offset_seconds` | How far the pump's clock is set ahead of UTC, apart from the skew. Read-only, and the quantity a decoder subtracts back out. |
| `pump_offset_seconds` | A genuine **skew**: a lie the pump tells about the time, stacked on the offset, which moves every wire timestamp without touching delivery arithmetic. |

Setting the pump's date and time — `ChangeTimeDateRequest` from the driver, or
`POST /api/state/time` (`FaketandemClient.setPumpTimeOnThePump`) for a user on the pump's own
screen — moves `pump_timezone_offset_seconds` and writes the pump's `TimeChanged` (13) and
`DateChange` (14) records, stamped on the new clock. Records already in the log keep their old
stamps, so each record in `/api/history` carries the `wire_offset_seconds` it was written
under.

One rule governs every time field the harness reports. Wall-clock fields (`time`,
`start_time`, `end_time`, `temp_start`, `temp_end`, `cleared_time`) are **true instants**
on the pump's Clock, RFC 3339 in UTC. `*_pump_seconds` / `pump_seconds` / `pump_time`
fields are **what went on the wire**, with both offsets applied. Either is derivable from
the other:

```
unix(time) = pump_seconds + 1_199_145_600 - wire_offset_seconds
```

where `wire_offset_seconds` is `pump_timezone_offset_seconds + pump_offset_seconds` for
anything written since the clock was last set.

`ConformanceClock` sets the emulator's clock to the test process's own local time and leaves
`pump_offset_seconds` at 0, so a dose's second on the driver side is the second the pump
recorded; `setSkew(_:)` adds a real skew on top for the clock-skew scenarios. The phone's zone
is moved with `PhoneTimeZone`, which sets `TZ` (`NSTimeZone.default` does not reach
`TimeZone.current` on Linux); `reset()` sets the pump back to the phone's local time.

Each conformance scenario starts its clocks a minute after the newest record on the emulator,
or at real time if that is later. Earlier scenarios run their clocks ahead of real time, and a
fresh driver starting behind their records would find them in its future and report them as
new.

### History records

`GET /api/history?since=&limit=` is the full feed (`since` exclusive, `next_since` to
resume, `truncated` when the limit cut the page short). The 50-record tail in `GET
/api/state` stays as a convenience, but a scenario that runs for a while loses records off
its front without being told, so `PumpTimeline` is built from the feed.

Each record separates what the wire carries from what it cannot. `data` holds the record's
own wire fields, named exactly as pumpX2 and TandemKit name them and nothing else —
`BolusActivated` `bolusSize`, `BolusCompleted` `insulinDelivered` / `insulinRequested` /
`completionStatusId`, `TempRateActivated` `percent` / `durationMilliseconds` /
`tempRateId`, `TempRateCompleted` `tempRateId` / `timeLeft`, `PumpingSuspended` `reasonId`,
`AlarmActivated` and `AlarmCleared` `alarmId`. `extra` holds the pump-side context a
26-byte record has no room for: a bolus's `bolusSourceId`, a temp rate's `tempRate` /
`normalRate` / `deliveredUnits`, the string `reason` behind a suspend, the
`alertTypeName` behind an alarm. `source_nibble` is the high nibble of the type-id word.

`completionStatusId` is the end reason, and it decodes as pumpX2's
`LastBolusStatusAbstractResponse.BolusStatus`: 0 `STOPPED_USER_TERMINATED`, 1
`STOPPED_ALARM`, 2 `STOPPED_MALFUNCTION`, 3 `COMPLETE`, 4 `STOPPED_WIRELESS`, 5
`REJECTED_WIRELESS`, 6 `TERMINATED_PLGS`.

`GET /api/state` also carries `alarms_history`: every alarm that has been raised *and*
cleared, with both ends of the interval. `alerts` only ever reports what stands now, so
without it an alarm that came and went leaves nothing a timeline can close.

### Assertions have two sides

Every flow asserts what the driver told the host (`MockPumpManagerDelegate`, driver
state) **and** what the pump saw (`/api/state`, `/api/log`). The request log gives each
parsed inbound message with its opcode and fragments, each response with how many
fragments went out, and every connection change, so "the pump never answered" and "the
driver ignored the answer" are distinguishable. `harness.requestsSeen()` returns the
inbound messages since the last reset; each test attaches the whole log to its result.

## The tests

Each test class's header comment says what it covers. The dose-reporting scenarios are indexed in
[conformance-test-plan.md](conformance-test-plan.md).

### Pairing method

`FaketandemHarness.pair(_:)` defaults to `PairingMethod.seededLongTermKey`: the harness
generates a random 32-byte key, hands it to the pump (`setLongTermKey`) and to the driver
(`pumpState.derivedSecret`), and the connect authenticates through
`Jpake3SessionKeyRequest`/`Jpake4KeyConfirmationRequest` alone — the state a driver is in
after any completed pairing. Both sides derive the session key as
`HKDF(serverNonce, longTermKey)`, so this is a real authentication, not a bypass. Use
`.fresh` for the onboarding flow: faketandem drives pumpX2's `jpake-server` over pipes, so
it runs on macOS too, and `PairingIntegrationTests` covers it — it just costs a subprocess
and a few seconds per pairing.

## Adding a test

1. Subclass `FaketandemIntegrationTestCase`. `setUpWithError` skips without the
   environment and resets the emulator; `tearDownWithError` shuts the driver down and
   attaches the request log.
2. `let driver = makeDriver()` (optionally with a seeded `TandemPumpManagerState` or a
   clock), then `try harness.pair(driver)` when an authenticated session is the
   precondition. `makeDriver` also marks setup's basal sync done
   (`hasSyncedBasalRateSchedule`), so a test can set temp basals without syncing a schedule
   first; pass `stageBasalScheduleSync: false` to start from a driver that has never synced, and
   `attachDelegate: false` for a setup flow's, which no host has adopted yet.
   `reset()` puts the emulator's profile back to its default (one segment, 0.85 U/hr);
   `client.setIDPProfiles` stages another, or none.
3. Stage the pump with `harness.client` (`setState`, `startBolus`, `suspend`, `setClock`,
   `armFault`, …), drive the driver, and wait with `IntegrationWait.until` /
   `IntegrationWait.value` or `ResultBox` rather than sleeping.
4. Assert on `driver.delegate` / `driver.manager.state` and on
   `harness.client.snapshot()` / `harness.requestsSeen()`.
   `shutDownDriver()` ends a driver as the app going away does, for a relaunch: the host is told
   nothing. `deactivateDriver()` is the host deleting the pump manager (`delete()`),
   which finalizes every dose the host holds as mutable, so it is no relaunch. A setup flow's manager
   is made with `attachDelegate: false` and handed to the host with `Driver.adoptByHost()`, after
   `ConformanceTestCase.loadHistoryForSetup()` if the scenario loads the pump's history.
5. If the assertion fails because of the emulator, do not bend the driver: wrap the
   assertion in a strict `XCTExpectFailure` whose message names the emulator gap, list the
   gap under "Known emulator gaps", and keep the pump-side evidence in the test. Strict is
   the point: when the emulator is fixed the wrapper becomes an unexpected pass and the
   suite tells you to take it out.

New files under `Tests/TandemKitIntegrationTests/` must be members of the
`TandemKitIntegrationTests` target; `ruby scripts/check_xcodeproj_source_membership.rb
--fix` does it. On Linux SwiftPM picks them up from the directory, except `Conformance/Oracles`,
which `TandemKitTests` compiles because both test targets use it.

## Trio in the simulator

`TrioIntegrationTests` run Trio itself, built from `nightscout/Trio` `feat/tandem-closed-beta` with
this TandemKit as its submodule and `VirtualPump.xcconfig` applied to the whole build, so Trio's own
`DeviceDataManager` and pump history take the driver's reports instead of `TrioDoseStoreOracle`.
Nothing in Trio changes for it:

- `scripts/trio-test.sh build` builds Trio (signed ad hoc, since an unsigned simulator build has
  no entitlements and Trio stops when the keychain refuses its first write; `CI=true` to skip its
  SwiftFormat and Crashlytics phases; bundle id `org.nightscout.$TRIO_TEAM.trio`; without
  ThreadSanitizer, see below) and the test bundle.
- `scripts/trio-test.sh test` starts faketandem and `scripts/app-launcher.py --host trio`, and hands
  the launcher's address to the bundle. The tests run in the simulator and cannot reach `simctl`, so
  before each test `TrioTestCase` asks the launcher for a fresh install of Trio (`/install`) and to
  launch it (`/launch`, with any launch arguments), and a test can stop and start it again on the
  same data and arguments (`/relaunch`, with files to write over that data first, which is how a
  deleted pump manager is made again). The first `/install` of a run uninstalls and installs the
  app; the later ones keep the install the launcher made and put its data container back to what a
  new one holds (every file gone, the container's metadata and empty directories kept) and restart
  the simulator's `cfprefsd`, which would otherwise answer the last test's UserDefaults from memory.
  `/install?fresh=1`, a rebuilt app at `--app` and a container that cannot be emptied each
  uninstall and install again. The launcher then seeds the data container with what a set-up install
  holds: `onboardingCompleted`, an unpaired Tandem pump manager (`PumpManagerState.plist`:
  `managerIdentifier` `TandemPumpManager`, empty `state`) and both telemetry streams off (Trio's
  default is on). The test writes Trio's own settings over that (`seededFiles`): Trio's default
  limits in `settings/settings.json` and a 1 U/hr `settings/basal_profile.json`, plus whatever a
  scenario needs. Trio is launched with `TANDEMKIT_VIRTUAL_PUMP` and `TANDEMKIT_VIRTUAL_PUMP_CONTROL`,
  and the launcher answers once the control port accepts. Around each test faketandem's delivery,
  profile and limits are put back, which `harness.reset()` leaves.
- The tests reach the driver inside Trio through `VirtualPumpControl.Client`: `pair` (with a
  long-term key the test also gives faketandem, so only the quick-reconnect rounds run, or without
  one through the whole JPAKE exchange), `applyOnboardingSettings`, `bolus`, `cancelBolus`,
  `syncBasalSchedule`, `syncPumpTime`, `tempBasal` (a duration of 0 cancels), `suspend`, `resume`,
  `recordCartridgeChange`, `recordSiteChange`, `setFeatureFlag`, `deletePumpManager`
  (`delete()`, as the pump settings screen's remove does; nothing reaches the manager
  afterwards), `sync`, `status`, and `pumpEventBatches`, every batch handed to Trio with Trio's
  completion. Trio completes a batch once it has saved it, so a completed log is all in the store.
  What the pump does on its own (a suspend, a bolus from its screen, a dropped link) goes through
  faketandem's API.
- They read Trio's Core Data store (`TrioCoreDataPersistentContainer.sqlite`, WAL) read-only in
  place (`TrioStore`), between two reads of the batch log that agree, and compare its rows with
  `TrioDoseStoreOracle` fed the same batches, using Trio's `maxBasal` and the bolus increment it
  rounds to, seeded as the pump's 0.05 U (see below).

The commands call the driver as Trio's code would. `TrioClosedLoopTests` runs Trio's own loop
instead: Trio's glucose simulator as the CGM (`cgm` `simulator`, held near 250 mg/dL through its
`GlucoseSimulator_*` defaults passed as launch arguments), closed loop, a max IOB and SMBs allowed.
Trio loops on each reading of the simulator, 5 minutes apart, and the first is at launch, so the
scenario seeds `PumpManagerState.plist` with the driver's state after a pairing (`beforeLaunch`: the
schedule as synced, a long-term key faketandem is given too, and the peripheral id faketandem sends
in its `hello`, read with `FaketandemHarness.readHello`) and the pump's profile as the schedule: the
loop at launch reaches a paired pump and `APSManager` enacts a temp basal and an SMB through the
driver about 15 s in, where a pairing through the control channel after launch lost the race to
that loop and waited for the next reading. Trio's manual bolus path (`APSManager.enactBolus`, from
its bolus screen) is not driven, nor is its pump setup flow, which hands Trio the manager only once
paired: every other scenario pairs a manager Trio holds from launch, as when re-pairing. The
cartridge and fill cannula wizards wait for state-stream notifications faketandem does not send, so
their scenario sends what they report once done, around a suspend.

`TrioPumpDeletionTests` delete the pump manager, once while it is connected and once after the pump
refused the code, and pair a new one on the pump's code: the pump's link goes down and stays down,
no command reaches the deleted manager, and the new one pairs from the first JPAKE round, so Trio and
the pump end up holding a key the deleted manager never had. The setup screen that makes the new
manager is not driven: `recreatePumpManager` relaunches Trio with an unpaired manager seeded in
`PumpManagerState.plist`, and Trio restores it as it restores every scenario's manager. Trio's
`DeviceDataManager` writes that file only when it takes a manager, so the deleted one's stays and a
relaunch without the seed would bring the deleted pump back; the test holds that as a strict
expected failure, which becomes an unexpected pass once Trio removes the file.

`trio.log` (the simulator's log stream, every launch) and `app-launcher.log` land in `LOG_DIR`, and
each test's Trio `Documents/logs`, TandemKit log and store in `LOG_DIR/<test>`. A failed test also leaves
`trio-sample.txt` there, a few seconds of Trio's stacks that the launcher takes with `sample` before
stopping it, since a Trio that stops answering logs nothing about why. The `trio` job in
`.github/workflows/macos.yml` runs it on the self-hosted runners.

## Loop in the simulator

`LoopIntegrationTests` run Loop the same way, built from `LoopKit/LoopWorkspace`
`feat/tandem-closed-beta` with this TandemKit as its `TandemKitPlugin` and `VirtualPump.xcconfig`
applied to the whole workspace. They cover what Trio cannot: upstream LoopKit, the plugin build, and
LoopKit's `DoseStore`, the store `LoopDoseStoreOracle` models, so they check the oracle against the
real thing as well as the driver against the oracle.

- `scripts/loop-test.sh build` builds the `LoopWorkspace` scheme signed ad hoc with no team, as Trio
  is. Loop derives its bundle id and app group from the team, so the script sets
  `MAIN_APP_BUNDLE_IDENTIFIER` to `com.$LOOP_TEAM.loopkit.Loop` (app group
  `group.com.$LOOP_TEAM.loopkit.LoopGroup`). It builds everything else first, under a copy of
  that scheme without Loop in the workspace's `xcuserdata`: Loop's Install Plugins phase
  embeds whichever plugins it finds built, and Loop depends on none of them, so in one parallel
  build a plugin still building was embedded without its Info.plist.
- `scripts/loop-test.sh test` runs `scripts/app-launcher.py --host loop`. Loop keeps its store
  (`com.loopkit.LoopKit/Model.sqlite`) and its settings and onboarding state (the UserDefaults suite
  named by `AppGroupIdentifier`) in its app group container, which the simulator keeps across
  reinstalls. On each install the launcher empties it, keeping the container's metadata, writes the
  suite, and restarts the simulator's `cfprefsd`, which would otherwise answer from memory. It seeds
  `Documents/PumpManagerState.plist` with an unpaired Tandem pump and sets
  `com.loopkit.Loop.OnboardingManager.IsComplete`; the test adds Loop's therapy settings as the legacy
  keys its `SettingsManager` migrates at launch (`LoopTestCase.groupDefaults()`), closed loop off
  unless a scenario turns it on.
- Loop asks for notification and Health access when it completes onboarding, and the prompts wait
  for a tap no test makes. Only the home screen waits behind them: Loop creates its pump manager,
  `DoseStore` and loop before onboarding, so the control channel, the store and Loop's own loop run.
- `assertLoopStoredWhatTheOracleExpects` reads both of `DoseStore`'s tables read-only in place
  (`LoopStore`): every `PumpEvent` row, and every `CachedInsulinDeliveryObject`, live or soft-deleted,
  row for row against `LoopDoseStoreOracle` fed the same batches. TandemKit records no basal profile
  starts, so `DoseStore` fills each gap before a basal dose with Loop's schedule
  (`BasalRateSchedule …` identifiers). The oracle models the fill when given the schedule
  (`basalSchedule:`), since it moves `lastImmutableBasalEndDate`. A fill's first piece starts a day
  before the save, on Loop's clock where the oracle has the driver's, so it is compared to a minute.
  `DoseStore` overlays a save before `InsulinDeliveryStore` has stored the last one's, so saves either
  side of a second store that piece twice, under each start; the repeat is not compared. No piece may
  overlap a basal dose the driver reported.

The scenarios are the ones `TrioIntegrationTests` run, plus Loop's own closed loop under each dosing
strategy, on its CGM simulator (`MockCGMManager`, restored from `Documents/CGMManagerState.plist`,
held at 250 mg/dL with a reading a minute): a temp basal with temp-basal-only dosing, and an
automatic bolus with automatic-bolus dosing. Where Loop differs: it counts what the pump ran for a
temp above its maximum basal rate, where Trio drops it, and it does not sync its delivery limits to
the pump at launch, as Trio does. A scenario that resumes waits a second after the suspend, as its
Trio twin does, for Loop's own reason: the driver dates a resume at least a second after its
suspend, ahead of Loop's clock inside that second, and `DoseStore` caches no finished dose that
ends ahead of its clock, so a suspend resumed sooner stays open in `CachedInsulinDeliveryObject`
until the next batch that is not empty. The other waits in Trio's scenarios are for its own
same-second ordering, which Loop does not have.

`LoopPumpDeletionTests` are `TrioPumpDeletionTests`' twins: deleting the pump manager, connected and
after a refused code, then pairing a new one Loop restores from a seeded `PumpManagerState.plist` at
a relaunch. Loop removes that file when it lets a pump manager go, which the test waits for.

`loop.log`, `app-launcher.log` and each test's TandemKit log and Loop store land in `LOG_DIR` as for
Trio, with `loop-sample.txt` for a failed test. The `loop` job in `.github/workflows/macos.yml` runs it
on the self-hosted runners.

## Trio behaviour the scenarios step around

Three things in Trio that the scenarios step around:

- Trio's scheme builds it with ThreadSanitizer, which reports a race in Trio at launch:
  `DeviceDataManager` writes `rawPumpManager` in `pumpManager.didSet` on the main thread, after
  setting the delegate queue, and in `pumpManagerDidUpdateState` on that queue, which the driver
  calls once both are set. Now and then the runtime deadlocked symbolizing that report: the main
  thread, inside the report, waited on libc's `localeconv_l` lock, held by a thread that was
  itself waiting on TSan. Trio, its control server included, stopped answering, and the test failed
  on `timedOut` 300 s later, whichever scenario it was. `-enableThreadSanitizer NO` left
  `xcodebuild build` instrumenting it all the same, so `trio-test.sh` builds Trio from a copy of its
  scheme with the sanitizer off (`TrioWithoutThreadSanitizer`, in `Trio.xcodeproj/xcuserdata`,
  which Trio's git ignores), and refuses, at build and before testing, an app that links the TSan
  runtime. The reports went to Trio's stderr, which the launcher discards, so the lane loses
  nothing. tandemkit-stress is the lane that runs Trio under TSan and reads its reports.

- Trio rounds the boluses it stores to the bolus increment it loaded at launch. `DeviceDataManager`
  writes the pump's 0.05 U to `preferences.json` when it sets up the pump manager, but not to the
  preferences Trio holds, so until the next launch a 0.35 U SMB is stored as 0.3 U and a 0.05 U one
  as 0.1 U. The scenarios seed 0.05 U, as Trio holds it from that next launch.
- Trio stores a row dated ahead of its clock at its clock (`PumpHistoryStorage`). The driver dates
  a resume a second after a suspend in the same second, since Trio's IOB throws on that pair, but a
  resume that reaches Trio within that second is pulled back into it. The scenarios wait a second
  between such commands.

## faketandem over real Bluetooth

The [unified pump simulator](https://github.com/bastiaanv/unified-pump-simulator)'s Tandem tab is a
CoreBluetooth peripheral that fronts faketandem's virtual GATT link: the Mac advertises as the pump
and forwards every subscription, write and read a phone makes, so TandemKit on a phone pairs and
runs against the emulator over the air, built as it ships, with faketandem's harness API driving
the pump side. It is the way to run the manual test plan's flows without a pump.

A CoreBluetooth peripheral cannot advertise manufacturer data, which is where the scan reads a
pump's pairing step, so the simulator says so in its name (`Tandem Mobi Simulator 123`; any name
with `SIM` or `Simulator` in it, `TandemPumpScan.isSimulatorName`) and `TandemKitScanViewModel` takes
that as a pump at the code-entry step (`advertisedPairingStep`). Nor can it end a connection: when faketandem drops the link, the
simulator withdraws its services, so the driver sees its next request fail rather than the
`peripheralDisconnected` a pump gives, and the handshake-failure count is not exercised that way.

## Known emulator gaps

- **A bolus permission is granted while a bolus runs** (the `TODO` in faketandem's
  `BolusPermissionHandler`), and the `InitiateBolusRequest` that follows replaces the running
  bolus. A pump refuses the permission (#504). No test is bent by it: the driver never asks while
  a bolus it started runs, but if that broke, `DeliveryLimitIntegrationTests` L8–L11 would show a
  second bolus replacing the first rather than the pump's refusal.
- **A bolus writes no `BolusDelivery` (280) records.** The source given to
  `/api/state/bolus/start` reaches only `BolusActivated`'s `extra` and the bolus status. A pump
  writes one of these records when a bolus starts and another when it completes, and they carry
  the source the driver takes a history bolus's `automatic` from. Conformance D16 appends them
  itself.
- **A running temp's start is stamped on the clock in force now.** faketandem's `TempRateHandler`
  encodes the start with the pump's current clock setting, where a Mobi keeps the stamp it began
  under, an hour ahead of the phone after the pump's clock was set back for DST. No test is bent by
  it: conformance G5 and the Trio and Loop Sync Time scenarios run with the start on the new clock,
  and `DeliveryTransitionReportingTests` covers the stale stamp.
- **No extended bolus is delivered.** faketandem's bolus runs only an up-front part. Conformance D13
  and group J (`ExtendedBolusConformanceTests`) append the records a pump writes for one
  (`ExtendedBolusHistory.swift`), so nothing checks that the emulator would write them in that order.

One behaviour is opt-in: faketandem runs the pump's 5-minute basal cycle, and follows profile
segment boundaries, only with `basal_cycle_enabled` (faketandem README "Basal cycle"). Conformance
group H (`BasalHistoryConformanceTests`) turns it on and `FaketandemHarness.reset()` turns it off;
every other scenario runs with basal delivered continuously and no BasalDelivery records, and stages
the rate in force with `basal_rate`.

Not gaps, but worth knowing when reading timings: `FaketandemHarness.makeDriver` shortens the
driver's response timeout to 2 s and its connect timeout to 15 s (`VirtualPump.responseTimeout`,
`VirtualPump.connectTimeout`; production keeps 30 s for a real pump's slowest command), so a
scenario that drops a response waits 2 s, not 30, and the reconnect retry's backoff to 1, 2, 3, 4,
5 s (`reconnectRetryDelays`; production waits 5, 10, 20, 40, 60 s). It also shortens the history fetcher's per-chunk
pacing (`VirtualPump.historyPacing`) to a 50 ms request delay and poll and a 2 s chunk timeout,
from ControlX2's 1 s, 0.5 s and 8 s (`HistoryLogFetcher.Pacing.production`), so a 255-entry
`HistoryLogRequest` costs milliseconds rather than a second and a lost stream record waits 2 s,
not 8, before the gap-healing pass. An unauthenticated `DisconnectPumpRequest` is
not answered (the handler requires auth, as on a real pump), so the driver sends it only on an
authenticated session. And pairing-state `NotDiscoverable` still answers `hello` (followed by
`disconnect`), which the virtual `CBCentralManager` treats as "not advertising".
