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

The script builds faketandem from `FAKETANDEM_DIR`, starts it with `-transport virtual`
on two free loopback ports, waits for its API, runs the `TandemKitIntegrationTests`
scheme through `scripts/test-local.sh`, and kills the emulator on exit. Logs:

| File (under `LOG_DIR`, default `.derived-data-virtual-pump/integration-logs/`) | Contents |
| --- | --- |
| `faketandem.log` | The emulator's log: every fragment received and sent, every handler decision. |
| `xcodebuild.log` | The driver's `TandemLogger` output and the XCTest results. |
| `TandemKitIntegrationTests.xcresult` | The result bundle; each test attaches the pump's request log (`xcrun xcresulttool export attachments --path … --output-path …`). |

Environment variables the script reads: `FAKETANDEM_DIR`, `FAKETANDEM_JAR`, `FAKETANDEM_BIN`,
`FAKETANDEM_ARGS` (extra emulator flags), `FAKETANDEM_HOST`, `LOG_DIR`, plus everything
`scripts/test-local.sh` reads (`TRIO_PRODUCTS`, `DERIVED_DATA`, `SIMULATOR`, `DESTINATION`). The script
sets `VIRTUAL_PUMP=1` for `test-local.sh`, which adds `-xcconfig VirtualPump.xcconfig`, and
defaults `DERIVED_DATA` to `.derived-data-virtual-pump` so the flagged build does not
invalidate the plain one.

In CI, the `integration` job in `.github/workflows/macos.yml` runs this script on the self-hosted
macOS runners for every push, pull request and manual run, once the `unit` job has passed. It builds
TandemKit with `VirtualPump.xcconfig` in the background while faketandem is built from its default
branch (`faketandem_ref` on a manual run picks another) and the cliparser jar fetched, then hands
the binary to the script as `FAKETANDEM_BIN`. The job fails if any integration test skips, because
a skip means the emulator's addresses never reached the test process.

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

### Pump time is local time

A Tandem pump keeps its clock in **local time with no zone attached**: its pump-epoch
seconds count from 2008-01-01 00:00:00 as read on the pump's own clock, and every consumer
decodes on that assumption — TandemKit's `Dates.fromJan12008ToUnixEpochSeconds` subtracts
`TimeZone.current.secondsFromGMT()`. The emulator encodes the same way, so two separate
offsets sit between its clock and the wire and they mean different things:

| `/api/clock` field | Meaning |
| --- | --- |
| `pump_timezone` | The IANA zone the pump keeps its clock in; settable, which is how a test reproduces a traveling pump or a DST boundary. `UTC` turns the convention off. |
| `pump_timezone_offset_seconds` | That zone's offset in force at `pump_now`. Read-only, and the quantity a decoder subtracts back out. |
| `pump_offset_seconds` | A genuine **skew**: a lie the pump tells about the time, stacked on the zone, which moves every wire timestamp without touching delivery arithmetic. |

One rule governs every time field the harness reports. Wall-clock fields (`time`,
`start_time`, `end_time`, `temp_start`, `temp_end`, `cleared_time`) are **true instants**
on the pump's Clock, RFC 3339 in UTC. `*_pump_seconds` / `pump_seconds` / `pump_time`
fields are **what went on the wire**, with both offsets applied. Either is derivable from
the other:

```
unix(time) = pump_seconds + 1_199_145_600 - pump_timezone_offset_seconds - pump_offset_seconds
```

`ConformanceClock` puts the emulator in the test process's own zone and leaves
`pump_offset_seconds` at 0, so a dose's second on the driver side is the second the pump
recorded; `setSkew(_:)` adds a real skew on top for the clock-skew scenarios.

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
- `FaketandemControlSocket` is the websocket surface for what only exists as websocket
  commands: pairing code, long-term key, pump-side disconnect, and the pairing status with
  the key bytes. One socket is shared for the whole test process; the emulator accepts
  several, but one is all the tests need.
- `IntegrationWait` polls a condition while pumping the run loop; `ResultBox` carries a
  completion result to a polling wait. Neither blocks the main thread outright, because
  parts of the driver complete on the main queue.

### Assertions have two sides

Every flow asserts what the driver told the host (`MockPumpManagerDelegate`, driver
state) **and** what the pump saw (`/api/state`, `/api/log`). The request log gives each
parsed inbound message with its opcode and fragments, each response with how many
fragments went out, and every connection change, so "the pump never answered" and "the
driver ignored the answer" are distinguishable. `harness.requestsSeen()` returns the
inbound messages since the last reset; each test attaches the whole log to its result.

## The tests

| File | Covers |
| --- | --- |
| `ScanIntegrationTests` | Scan discovers the virtual pump with the identifier and name from `hello`; the manufacturer byte tracks `PairStep1/2/DiscoverableOnly`; a `NotDiscoverable` pump is not advertised. |
| `PairingIntegrationTests` | Fresh JPAKE pairing through every round; wrong code refused; seeded long-term key authenticates through rounds 3/4 only. |
| `SyncIntegrationTests` | `syncPumpData` reports a status update, one reservoir reading, the reconciliation boundary as an empty non-replacing batch; a second sync is quiet and advances the boundary. |
| `BolusIntegrationTests` | `enactBolus(1.0)`: BolusPermission then InitiateBolus on Control, the mutable dose event, the pump's bolus record (source id 8), then finalization from `LastBolusStatus` with the same `raw`/`syncIdentifier`. |
| `ReconnectIntegrationTests` | A pump-side drop is followed by a quick reconnect (round 3 first, key unchanged) and the new session serves a sync; a driver rebuilt from persisted `rawValue` reaches the pump on its first command. |
| `Conformance/` | The dose-reporting conformance groups A–D (`docs/conformance-test-plan.md`): interrupts, cancels, idempotency and pump-side failures, each ending in a diff of the host's stored doses against `PumpTimeline`. |
| `MTUIntegrationTests` | The same pair/sync/bolus traffic at both framings: at ATT MTU 247 every response that fits arrives in one notification and the flow still runs; at the default 23 the same responses are cut into 18-byte chunks and the driver reassembles them. |

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
   precondition.
3. Stage the pump with `harness.client` (`setState`, `startBolus`, `suspend`, `setClock`,
   `armFault`, …), drive the driver, and wait with `IntegrationWait.until` /
   `IntegrationWait.value` or `ResultBox` rather than sleeping.
4. Assert on `driver.delegate` / `driver.manager.state` and on
   `harness.client.snapshot()` / `harness.requestsSeen()`.
5. If the assertion fails because of the emulator, do not bend the driver: wrap the
   assertion in a strict `XCTExpectFailure` whose message names the emulator gap, list the
   gap under "Known emulator gaps", and keep the pump-side evidence in the test. Strict is
   the point: when the emulator is fixed the wrapper becomes an unexpected pass and the
   suite tells you to take it out.

New files under `Tests/TandemKitIntegrationTests/` must be members of the
`TandemKitIntegrationTests` target; `ruby scripts/check_xcodeproj_source_membership.rb
--fix` does it. The directory is deliberately not declared in `Package.swift`'s Linux
branch (JPAKE is a trapping stub there).

## What the harness found

Two driver bugs, fixed in the same change that added the harness and covered by unit
tests in `TandemKitTests` (`VirtualCoreBluetoothTests`, `BTResponseParserTests`):

- Continuation packets of a multi-packet response were dropped. `TandemPeripheralManager`
  only handed a notification to the pending write when byte 2 matched the expected opcode;
  continuation packets carry cargo there and can arrive before the writing thread has
  re-armed for them. Responses are now reassembled on the notification path.
- `BTResponseParser` rejected 3-byte packets, which is exactly what the last packet of a
  message whose length is 1 mod 18 looks like (`Jpake4KeyConfirmationResponse`).

Both were latent on real hardware because a Mobi negotiates a large MTU and most
responses fit one notification; faketandem fragments every response into 20-byte
notifications, as pumpX2's cliparser does and as a 23-byte-MTU pump would.

## Known emulator gaps

One open, in `PumpSideConformanceTests` (plan D3):

- **An armed `error_response` is applied on the response path**
  (`pkg/handler/router.go` `sendWithFaults`), after the handler has already run. A pump
  answering `ErrorResponse` to `InitiateBolusRequest` did not start the bolus; the emulator
  starts it and then replaces the answer, so the driver's error arrives over a pump that is
  delivering.

Everything else the harness found has been fixed in faketandem. What was fixed, because the
shape of it explains what the harness is for:

- **A driver-commanded temp-rate stop wrote no `TempRateCompleted` record.** The handler
  applied a basal state with the temp rate cleared and recorded only activations, and a
  suspend set a flag, so a temp rate a driver stopped — or replaced, or suspended away —
  stayed open forever in a timeline built from the history log and no cancel-or-replace
  scenario could close its diff. Every path that ends delivery now goes through one writer
  (`pkg/state/delivery.go`), which records the ending exactly once at the true end instant.
- **Wire timestamps were pump-epoch seconds counted from UTC.** A real pump counts from its
  own local clock, so every timestamp the driver decoded landed one UTC offset away from
  the pump's own record — four hours in EDT — which is invisible until something compares a
  dose's second. The pump's zone is a first-class setting now, and separate from the skew.
- **History records were assembled at each call site**, so the same event reached a driver
  with different field names depending on which path produced it, and the simulator's
  `BolusCompleted` carried no end reason at all — a completed bolus was indistinguishable
  from a canceled one. One writer per type settles it.
- **A canceled bolus was reported with end reason 2**, which is `STOPPED_MALFUNCTION`: every
  cancel looked to a driver like a pump malfunction. It is 0, `STOPPED_USER_TERMINATED`.

- **Fresh JPAKE pairing could not run on macOS.** faketandem spawned pumpX2's
  `jpake-server` through `goexpect`, whose `goterm` `OpenPTY` issues the Linux-only
  `TIOCSPTLCK` ioctl; macOS answered `ENOTTY` and `Jpake1aRequest` went unanswered. It is
  driven over plain pipes now, and `testFreshJpakePairingAuthenticatesBothSides` runs all
  five rounds.
- **`InsulinStatusResponse.currentInsulinAmount` was scaled ×100.** The field is whole
  units on a real pump, so the driver reported a 137 U cartridge as 13699 U.
  `SyncIntegrationTests` asserts 137 directly.
- **The websocket handler kept one shared client** and cleared it on any close, so an older
  socket closing silenced a newer one. Concurrent clients are supported; the harness still
  keeps one socket per process (`FaketandemControlSocket.shared`) because one is enough.
- **`PUT /api/state {"pairing_code": …}` did not reach the pumpX2 bridge.** Every pairing
  code change goes through one update path now; the harness still uses the websocket
  `setPairingCode`, which returns the resulting pairing status in the same round trip.
- **Every response was fragmented into 20-byte notifications.** The ATT MTU is settable
  (`-virtual-mtu`, `GET`/`PUT /api/transport`, and announced as `att_mtu` in `hello`), so
  the unfragmented framing a real Mobi produces is exercised too — `MTUIntegrationTests`,
  and `FaketandemHarness.reset()` puts the MTU back to the 23-byte default before each test.

Not gaps, but worth knowing when reading timings: `FaketandemHarness.makeDriver` shortens the
driver's response timeout to 5 s and its connect timeout to 15 s (`VirtualPump.responseTimeout`,
`VirtualPump.connectTimeout`; production keeps 30 s for a real pump's slowest command), so a
scenario that drops a response waits 5 s, not 30. An unauthenticated `DisconnectPumpRequest` is
not answered (the handler requires auth, as on a real pump), so the driver sends it only on an
authenticated session. And pairing-state `NotDiscoverable` still answers `hello` (followed by
`disconnect`), which the virtual `CBCentralManager` treats as "not advertising".
