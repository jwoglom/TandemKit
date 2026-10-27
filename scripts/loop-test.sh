#!/usr/bin/env bash
# Run LoopIntegrationTests: Loop itself in the iOS simulator, on TandemKit's virtual pump build,
# against faketandem.
#
# Builds Loop from a LoopWorkspace checkout whose TandemKit is this revision (CI's checkout-loop
# action makes one), then starts faketandem and scripts/app-launcher.py, which installs Loop fresh for
# each test, seeded to start set up with an unpaired Tandem pump, and launches it with faketandem's
# address and a control-channel port (VirtualPumpControl). LoopIntegrationTests drive the driver
# inside Loop through that channel and read what Loop stored from its app group container. Logs land
# in LOG_DIR, with each test's TandemKit log and Loop's store under LOG_DIR/<test>.
#
# Usage:
#   scripts/loop-test.sh                  # build + test
#   scripts/loop-test.sh build [args...]  # Loop and the LoopIntegrationTests bundle; no emulator
#   scripts/loop-test.sh test [args...]   # test without building (args go to xcodebuild)
#
# Environment:
#   LOOP_DIR           LoopWorkspace checkout with this TandemKit at LOOP_DIR/TandemKit
#                      (default ../LoopWorkspace).
#   LOOP_DERIVED_DATA  Where Loop builds (default .derived-data-loop).
#   LOOP_TEAM          Placeholder team for Loop's bundle id, com.<team>.loopkit.Loop; the build is
#                      signed ad hoc, which needs no team (default TANDEMKITCI).
#   SIMULATOR_UDID     Simulator to install into (default: the booted one).
#   LOG_DIR            Default: $DERIVED_DATA/loop-logs.
#   Everything scripts/faketandem.sh reads, and scripts/test-local.sh for the test bundle
#   (TRIO_PRODUCTS, DESTINATION, DERIVED_DATA, which defaults to .derived-data-virtual-pump here).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_DIR="${LOOP_DIR:-$ROOT/../LoopWorkspace}"
LOOP_DERIVED_DATA="${LOOP_DERIVED_DATA:-$ROOT/.derived-data-loop}"
LOOP_TEAM="${LOOP_TEAM:-TANDEMKITCI}"
UDID="${SIMULATOR_UDID:-booted}"
FAKETANDEM_DIR="${FAKETANDEM_DIR:-$ROOT/../faketandem}"
FAKETANDEM_HOST="${FAKETANDEM_HOST:-127.0.0.1}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derived-data-virtual-pump}"
LOG_DIR="${LOG_DIR:-$DERIVED_DATA/loop-logs}"
export DERIVED_DATA VIRTUAL_PUMP=1 SCHEME=LoopIntegrationTests

mode="${1:-all}"; shift || true
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd)"
if [[ -d "$FAKETANDEM_DIR" ]]; then
  FAKETANDEM_DIR="$(cd "$FAKETANDEM_DIR" && pwd)"
fi
TEST_LOG="$LOG_DIR/xcodebuild.log"
RESULT_BUNDLE="$LOG_DIR/LoopIntegrationTests.xcresult"
LOOP_APP="$LOOP_DERIVED_DATA/Build/Products/Debug-iphonesimulator/Loop.app"

# Signed ad hoc with no team, as Trio is: Loop derives its bundle id and app group from the team, so
# the main bundle id is given outright. Loop's store and settings live in the app group, which an
# unsigned build would not have.
build_scheme() {
  local scheme="$1"; shift
  xcodebuild build -workspace "$LOOP_DIR/LoopWorkspace.xcworkspace" -scheme "$scheme" -configuration Debug \
    -destination "${DESTINATION:-platform=iOS Simulator,id=$UDID}" -derivedDataPath "$LOOP_DERIVED_DATA" \
    -xcconfig "$ROOT/VirtualPump.xcconfig" -skipMacroValidation -skipPackagePluginValidation \
    MAIN_APP_BUNDLE_IDENTIFIER="com.$LOOP_TEAM.loopkit.Loop" \
    DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
    "$@"
}

# LoopWorkspace's scheme with only its .loopplugin targets, in the workspace's git-ignored xcuserdata.
write_plugins_scheme() {
  local workspace="$LOOP_DIR/LoopWorkspace.xcworkspace"
  local schemes="$workspace/xcuserdata/$(id -un).xcuserdatad/xcschemes"
  mkdir -p "$schemes"
  python3 - "$workspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme" "$schemes/$PLUGINS_SCHEME.xcscheme" <<'EOF'
import sys
import xml.etree.ElementTree as ET

scheme = ET.parse(sys.argv[1]).getroot()
build = scheme.find("BuildAction")
entries = build.find("BuildActionEntries")
for entry in list(entries):
    if not entry.find("BuildableReference").get("BuildableName", "").endswith(".loopplugin"):
        entries.remove(entry)
if len(entries) == 0:
    sys.exit(f"no .loopplugin targets in {sys.argv[1]}")
for action in list(scheme):
    if action is not build:
        scheme.remove(action)
ET.ElementTree(scheme).write(sys.argv[2], encoding="UTF-8", xml_declaration=True)
EOF
}

PLUGINS_SCHEME="LoopWorkspacePlugins"
build_loop() {
  if [[ ! -f "$LOOP_DIR/LoopWorkspace.xcworkspace/contents.xcworkspacedata" || ! -d "$LOOP_DIR/TandemKit/Sources" ]]; then
    echo "No LoopWorkspace checkout with TandemKit at $LOOP_DIR; set LOOP_DIR" >&2
    exit 1
  fi
  # Loop's Install Plugins phase embeds each .loopplugin it finds, and Loop.app depends on none of
  # them, so the scheme's parallel build embedded one still building, with no Info.plist yet.
  write_plugins_scheme
  build_scheme "$PLUGINS_SCHEME" "$@"
  build_scheme LoopWorkspace "$@"
}

if [[ "$mode" == "build" ]]; then
  build_loop "$@" 2>&1 | tee "$LOG_DIR/xcodebuild-loop.log"
  "$ROOT/scripts/test-local.sh" build "$@"
  exit
elif [[ "$mode" == "all" ]]; then
  build_loop 2>&1 | tee "$LOG_DIR/xcodebuild-loop.log"
  "$ROOT/scripts/test-local.sh" build
elif [[ "$mode" != "test" ]]; then
  echo "unknown mode $mode" >&2
  exit 2
fi

if [[ ! -d "$LOOP_APP" ]]; then
  echo "No Loop build at $LOOP_APP; run '$0 build' first" >&2
  exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LOOP_APP/Info.plist")"

# shellcheck source=scripts/faketandem.sh
source "$ROOT/scripts/faketandem.sh"

LOG_STREAM_PID=""
LAUNCHER_PID=""
cleanup() {
  if [[ -n "$LAUNCHER_PID" ]]; then
    kill "$LAUNCHER_PID" 2>/dev/null || true
    wait "$LAUNCHER_PID" 2>/dev/null || true
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  if [[ -n "$LOG_STREAM_PID" ]]; then
    kill "$LOG_STREAM_PID" 2>/dev/null || true
  fi
  stop_faketandem
  grep -h -E 'Fatal error|Terminating app|EXC_[A-Z]+' "$LOG_DIR/loop.log" 2>/dev/null | tail -n 5 | sed 's/^/Loop stopped: /' >&2 || true
  echo "Loop log: $LOG_DIR/loop.log; launcher log: $LOG_DIR/app-launcher.log"
  echo "test log: $TEST_LOG"
}
trap cleanup EXIT
start_faketandem

# One stream for every launch.
xcrun simctl spawn "$UDID" log stream --style compact --level debug \
  --predicate 'process == "Loop" AND NOT subsystem BEGINSWITH "com.apple."' \
  > "$LOG_DIR/loop.log" 2>&1 &
LOG_STREAM_PID=$!

port_file="$LOG_DIR/app-launcher.port"
rm -f "$port_file"
python3 "$ROOT/scripts/app-launcher.py" --host loop --udid "$UDID" --app "$LOOP_APP" \
  --gatt "$GATT_ADDR" --log-dir "$LOG_DIR" --port-file "$port_file" > "$LOG_DIR/app-launcher.log" 2>&1 &
LAUNCHER_PID=$!
for _ in $(seq 1 100); do
  [[ -s "$port_file" ]] && break
  kill -0 "$LAUNCHER_PID" 2>/dev/null || { cat "$LOG_DIR/app-launcher.log" >&2; exit 1; }
  sleep 0.1
done
[[ -s "$port_file" ]] || { echo "app-launcher.py never listened" >&2; exit 1; }

# xcodebuild strips the TEST_RUNNER_ prefix and hands the rest to the test process.
export TEST_RUNNER_FAKETANDEM_GATT="$GATT_ADDR"
export TEST_RUNNER_FAKETANDEM_API_URL="$API_URL"
export TEST_RUNNER_LOOP_LAUNCHER_URL="http://127.0.0.1:$(cat "$port_file")"
rm -rf "$RESULT_BUNDLE"
set +e
# Every test takes over the one install of Loop.
"$ROOT/scripts/test-local.sh" test -resultBundlePath "$RESULT_BUNDLE" -parallel-testing-enabled NO "$@" 2>&1 | tee "$TEST_LOG"
status=${PIPESTATUS[0]}
set -e
echo "result bundle: $RESULT_BUNDLE"
exit "$status"
