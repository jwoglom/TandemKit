#!/usr/bin/env bash
# Run TrioIntegrationTests: Trio itself in the iOS simulator, on TandemKit's virtual pump build,
# against faketandem.
#
# Builds Trio from a checkout whose TandemKit is this revision (CI's checkout-trio action makes
# one), installs it fresh, writes the files that make it start already set up with an unpaired
# Tandem pump, and launches it with faketandem's address and a control-channel port
# (VirtualPumpControl). TrioIntegrationTests then drive the driver inside Trio through that
# channel and read what Trio stored from its data container. Logs land in LOG_DIR.
#
# Usage:
#   scripts/trio-test.sh                  # build + test
#   scripts/trio-test.sh build [args...]  # Trio and the TrioIntegrationTests bundle; no emulator
#   scripts/trio-test.sh test [args...]   # test without building (args go to xcodebuild)
#
# Environment:
#   TRIO_DIR           Trio checkout with this TandemKit at TRIO_DIR/TandemKit (default ../trio).
#   TRIO_DERIVED_DATA  Where Trio builds (default .derived-data-trio).
#   TRIO_TEAM          Placeholder team for Trio's bundle id, org.nightscout.<team>.trio; the build
#                      is signed ad hoc, which needs no team (default TANDEMKITCI).
#   SIMULATOR_UDID     Simulator to install into (default: the booted one).
#   LOG_DIR            Default: $DERIVED_DATA/trio-logs.
#   Everything scripts/faketandem.sh reads, and scripts/test-local.sh for the test bundle
#   (TRIO_PRODUCTS, DESTINATION, DERIVED_DATA, which defaults to .derived-data-virtual-pump here).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRIO_DIR="${TRIO_DIR:-$ROOT/../trio}"
TRIO_DERIVED_DATA="${TRIO_DERIVED_DATA:-$ROOT/.derived-data-trio}"
TRIO_TEAM="${TRIO_TEAM:-TANDEMKITCI}"
UDID="${SIMULATOR_UDID:-booted}"
FAKETANDEM_DIR="${FAKETANDEM_DIR:-$ROOT/../faketandem}"
FAKETANDEM_HOST="${FAKETANDEM_HOST:-127.0.0.1}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derived-data-virtual-pump}"
LOG_DIR="${LOG_DIR:-$DERIVED_DATA/trio-logs}"
export DERIVED_DATA VIRTUAL_PUMP=1 SCHEME=TrioIntegrationTests

mode="${1:-all}"; shift || true
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd)"
if [[ -d "$FAKETANDEM_DIR" ]]; then
  FAKETANDEM_DIR="$(cd "$FAKETANDEM_DIR" && pwd)"
fi
TEST_LOG="$LOG_DIR/xcodebuild.log"
RESULT_BUNDLE="$LOG_DIR/TrioIntegrationTests.xcresult"
TRIO_APP="$TRIO_DERIVED_DATA/Build/Products/Debug-iphonesimulator/Trio.app"

# CI=true skips Trio's SwiftFormat and Crashlytics build phases, which rewrite sources and upload.
# Signed ad hoc, not left unsigned: an unsigned simulator build carries no entitlements, the
# keychain then refuses every write, and Trio stops on its first one (BaseKeychain).
build_trio() {
  if [[ ! -f "$TRIO_DIR/Trio.xcworkspace/contents.xcworkspacedata" || ! -d "$TRIO_DIR/TandemKit/Sources" ]]; then
    echo "No Trio checkout with TandemKit at $TRIO_DIR; set TRIO_DIR" >&2
    exit 1
  fi
  xcodebuild build -workspace "$TRIO_DIR/Trio.xcworkspace" -scheme Trio -configuration Debug \
    -destination "${DESTINATION:-platform=iOS Simulator,id=$UDID}" -derivedDataPath "$TRIO_DERIVED_DATA" \
    -xcconfig "$ROOT/VirtualPump.xcconfig" -skipMacroValidation -skipPackagePluginValidation \
    DEVELOPER_TEAM="$TRIO_TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
    CI=true "$@"
}

if [[ "$mode" == "build" ]]; then
  build_trio "$@" 2>&1 | tee "$LOG_DIR/xcodebuild-trio.log"
  "$ROOT/scripts/test-local.sh" build "$@"
  exit
elif [[ "$mode" == "all" ]]; then
  build_trio 2>&1 | tee "$LOG_DIR/xcodebuild-trio.log"
  "$ROOT/scripts/test-local.sh" build
elif [[ "$mode" != "test" ]]; then
  echo "unknown mode $mode" >&2
  exit 2
fi

plist() {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">%s</plist>\n' "$2" > "$1"
}

# Trio reads these at launch (Documents/<key>.plist for its @PersistedProperty values): onboarding
# done, an unpaired Tandem pump manager, and both telemetry streams off, which are on unless
# explicitly false. settings/settings.json pins the pump limits the tests read back.
seed_trio() {
  local documents="$1/Documents"
  mkdir -p "$documents/settings"
  plist "$documents/onboardingCompleted.plist" '<true/>'
  plist "$documents/hasSeenFatProteinOrderChange.plist" '<true/>'
  plist "$documents/crashlyticsSharingEnabled.plist" '<false/>'
  plist "$documents/telemetrySharingEnabled.plist" '<false/>'
  plist "$documents/PumpManagerState.plist" \
    '<dict><key>managerIdentifier</key><string>TandemPumpManager</string><key>state</key><dict/></dict>'
  printf '{"insulin_action_curve": 10, "maxBolus": 10, "maxBasal": 2}\n' > "$documents/settings/settings.json"
}

wait_for_port() {
  python3 - "$1" "$2" <<'PY'
import socket, sys, time
port, timeout = int(sys.argv[1]), float(sys.argv[2])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        sys.exit(0)
    except OSError:
        time.sleep(1)
sys.exit(f"nothing listening on 127.0.0.1:{port} after {timeout:.0f}s")
PY
}

if [[ ! -d "$TRIO_APP" ]]; then
  echo "No Trio build at $TRIO_APP; run '$0 build' first" >&2
  exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TRIO_APP/Info.plist")"

# shellcheck source=scripts/faketandem.sh
source "$ROOT/scripts/faketandem.sh"

LOG_STREAM_PID=""
CONTAINER=""
cleanup() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  if [[ -n "$LOG_STREAM_PID" ]]; then
    kill "$LOG_STREAM_PID" 2>/dev/null || true
  fi
  if [[ -n "$CONTAINER" ]]; then
    # Trio's own log, and its store, for a failed run's artifacts. Simulated data only.
    cp -R "$CONTAINER/Documents/logs" "$LOG_DIR/trio-documents-logs" 2>/dev/null || true
    find "$CONTAINER" -name 'TrioCoreDataPersistentContainer.sqlite*' -exec cp {} "$LOG_DIR/" \; 2>/dev/null || true
  fi
  stop_faketandem
  grep -h -E 'Fatal error|Terminating app|EXC_[A-Z]+' "$LOG_DIR/trio.log" 2>/dev/null | tail -n 5 | sed 's/^/Trio stopped: /' >&2 || true
  echo "Trio log: $LOG_DIR/trio.log"
  echo "test log: $TEST_LOG"
}
trap cleanup EXIT
start_faketandem

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$TRIO_APP"
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
seed_trio "$CONTAINER"

CONTROL_PORT="$(free_port)"
xcrun simctl spawn "$UDID" log stream --style compact --level debug \
  --predicate 'process == "Trio" AND NOT subsystem BEGINSWITH "com.apple."' \
  > "$LOG_DIR/trio.log" 2>&1 &
LOG_STREAM_PID=$!
echo "Launching $BUNDLE_ID; data container $CONTAINER; control port $CONTROL_PORT"
SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP="$GATT_ADDR" SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP_CONTROL="$CONTROL_PORT" \
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
# TandemKit opens the channel when Trio creates its pump manager, after Core Data is up.
wait_for_port "$CONTROL_PORT" 180

# xcodebuild strips the TEST_RUNNER_ prefix and hands the rest to the test process.
export TEST_RUNNER_FAKETANDEM_GATT="$GATT_ADDR"
export TEST_RUNNER_FAKETANDEM_API_URL="$API_URL"
export TEST_RUNNER_TRIO_CONTROL_PORT="$CONTROL_PORT"
export TEST_RUNNER_TRIO_DATA_CONTAINER="$CONTAINER"
rm -rf "$RESULT_BUNDLE"
set +e
"$ROOT/scripts/test-local.sh" test -resultBundlePath "$RESULT_BUNDLE" "$@" 2>&1 | tee "$TEST_LOG"
status=${PIPESTATUS[0]}
set -e
echo "result bundle: $RESULT_BUNDLE"
exit "$status"
