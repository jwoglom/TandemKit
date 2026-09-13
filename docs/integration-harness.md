# Integration harness: TandemKit against faketandem

`TandemKitIntegrationTests` drives the real driver stack — `TandemPumpManager`,
`TandemBluetoothManager`, `TandemPeripheralManager`, JPAKE, message signing,
packetization — against [faketandem](https://github.com/jwoglom/faketandem), the Go
Tandem pump emulator, over its virtual GATT link. Nothing on the driver side is stubbed;
the only substitution is `SocketPumpCentral` standing in for CoreBluetooth one layer
below `TandemPeripheralManager`.

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

| File (under `LOG_DIR`, default `.derived-data/integration-logs/`) | Contents |
| --- | --- |
| `faketandem.log` | The emulator's log: every fragment received and sent, every handler decision. |
| `xcodebuild.log` | The driver's `TandemLogger` output and the XCTest results. |
| `TandemKitIntegrationTests.xcresult` | The result bundle; each test attaches the pump's request log (`xcrun xcresulttool export attachments --path … --output-path …`). |

Environment variables the script reads: `FAKETANDEM_DIR`, `FAKETANDEM_JAR`,
`FAKETANDEM_ARGS` (extra emulator flags), `FAKETANDEM_HOST`, `LOG_DIR`, plus everything
`scripts/test-local.sh` reads (`TRIO_PRODUCTS`, `DERIVED_DATA`, `SIMULATOR`).

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
 │           └ SocketPumpCentral/Peripheral ──┼── TCP ─────▶│  pkg/bluetooth VirtualTransport  │
 │             (newline JSON, GATT semantics) │             │   hello/attach/write/notify      │
 └────────────────────────────────────────────┘             └──────────────────────────────────┘
```

- `FaketandemHarness` reads the environment, holds the clients, resets the emulator
  before each test (`reset()`: drop any attached central, set the pairing code and clear
  the long-term key, real clock, no faults, `PairStep2`, empty request log), builds a
  `Driver`, and offers the flows the onboarding UI uses (`discover`, `pair`, `sync`).
- `Driver` is one real stack: `SocketPumpCentral` → `TandemBluetoothManager(central:)` →
  `TandemPumpManager(state:bluetooth:clock:)` with a `MockPumpManagerDelegate` attached in
  Trio's order (delegate, then queue). The clock is a `ManualClock` started at "now", so a
  test can move the driver's idea of time (bolus estimated end, sync throttles) without
  waiting; the emulator stays on its own clock unless a test drives `/api/clock`.
- `FaketandemClient` is the HTTP surface: pairing state, `/api/state` snapshot and direct
  writes, `/api/clock`, pump-initiated actions (bolus, temp basal, suspend/resume,
  history, qualifying events), the request log, faults, and the legacy settings table.
- `FaketandemControlSocket` is the websocket surface for what only exists as websocket
  commands: pairing code, long-term key, pump-side disconnect, and the pairing status with
  the key bytes. One socket is shared for the whole test process (see gaps).
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
| `PairingIntegrationTests` | Fresh JPAKE pairing (expected failure, see gaps); wrong code refused; seeded long-term key authenticates through rounds 3/4 only. |
| `SyncIntegrationTests` | `syncPumpData` reports a status update, one reservoir reading, the reconciliation boundary as an empty non-replacing batch; a second sync is quiet and advances the boundary. |
| `BolusIntegrationTests` | `enactBolus(1.0)`: BolusPermission then InitiateBolus on Control, the mutable dose event, the pump's bolus record (source id 8), then finalization from `LastBolusStatus` with the same `raw`/`syncIdentifier`. |
| `ReconnectIntegrationTests` | A pump-side drop is followed by a quick reconnect (round 3 first, key unchanged) and the new session serves a sync; a driver rebuilt from persisted `rawValue` reaches the pump on its first command. |

### Pairing method

`FaketandemHarness.pair(_:)` defaults to `PairingMethod.seededLongTermKey`: the harness
generates a random 32-byte key, hands it to the pump (`setLongTermKey`) and to the driver
(`pumpState.derivedSecret`), and the connect authenticates through
`Jpake3SessionKeyRequest`/`Jpake4KeyConfirmationRequest` alone — the state a driver is in
after any completed pairing. Both sides derive the session key as
`HKDF(serverNonce, longTermKey)`, so this is a real authentication, not a bypass. Use
`.fresh` for the onboarding flow; it cannot pass on macOS today (below).

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
   assertion in a strict `XCTExpectFailure` whose message names the emulator gap, add the
   gap below, and keep the pump-side evidence in the test.

New files under `Tests/TandemKitIntegrationTests/` must be members of the
`TandemKitIntegrationTests` target; `ruby scripts/check_xcodeproj_source_membership.rb
--fix` does it. The directory is deliberately not declared in `Package.swift`'s Linux
branch (JPAKE is a trapping stub there).

## What the harness found

Two driver bugs, fixed in the same change that added the harness and covered by unit
tests in `TandemKitTests` (`SocketPumpTransportTests`, `BTResponseParserTests`):

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

Each is asserted by a strict `XCTExpectFailure` where it blocks a test, so fixing the
emulator makes the test report "expected failure did not occur" and the wrapper can go.

1. **Fresh JPAKE pairing cannot run on macOS.** faketandem spawns pumpX2's `jpake-server`
   through `goexpect.SpawnWithArgs`, whose `goterm` `OpenPTY` issues the Linux-only
   `TIOCSPTLCK` ioctl on `/dev/ptmx`; macOS answers `ENOTTY` ("inappropriate ioctl for
   device"), the handler fails, and `Jpake1aRequest` is never answered (the driver times
   out after 30 s). Reproduce with
   `FAKETANDEM_TEST_CLIPARSER_JAR=… go test ./pkg/handler -run FullFlowViaJar` in the
   faketandem checkout. Affects `testFreshJpakePairingAuthenticatesBothSides` and
   `testPairingWithTheWrongCodeIsRefused`; every other flow uses the seeded key.
2. **`InsulinStatusResponse.currentInsulinAmount` is scaled ×100.**
   `pkg/handler/dynamic_status.go` sends `Reservoir.CurrentUnits * 100` (and the settings
   default is `20000` for 200 U), but real pumps report whole units — TandemKit's Sept 2026
   Mobi captures show 150/105/90, and faketandem's own `router.go` history code says the
   same. The driver reports a 137 U cartridge as 13699 U. Affects the reservoir
   assertions in `SyncIntegrationTests`.
3. **The websocket handler clears the shared client on any close.** `pkg/api/server.go`
   keeps one `conn` and its reader's `defer` sets it to nil unconditionally, so closing an
   older socket silences a newer one. The harness therefore keeps one socket for the
   whole process (`FaketandemControlSocket.shared`).
4. **`PUT /api/state {"pairing_code": …}` does not reach the pumpX2 bridge**, only the
   websocket `setPairingCode` does; the harness uses the websocket.
5. **Every response is fragmented into 20-byte notifications.** Faithful to a 23-byte
   MTU and to cliparser's output, and what exposed the two driver bugs above — but a real
   Mobi negotiates a larger MTU, so a `-virtual-max-att` style option would let tests
   choose either behaviour.

Not gaps, but worth knowing when reading timings: an unauthenticated
`DisconnectPumpRequest` is not answered (the handler requires auth, as on a real pump), so
a failed setup costs the driver its 30 s response timeout before the link drops; and
pairing-state `NotDiscoverable` still answers `hello` (followed by `disconnect`), which
`SocketPumpCentral` now treats as "not advertising".
