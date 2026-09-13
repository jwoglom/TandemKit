#!/usr/bin/env bash
# Run the TandemKitIntegrationTests scheme against a freshly built faketandem.
#
# Builds faketandem from a sibling checkout, starts it with the virtual GATT
# transport on free ports, waits for its API, runs scripts/test-local.sh for the
# integration scheme with the TEST_RUNNER_ environment the tests read
# (FaketandemHarness.swift), and tears the emulator down. Logs land in LOG_DIR.
#
# Usage:
#   scripts/integration-test.sh                       # build-for-testing + test
#   scripts/integration-test.sh test [xcodebuild args...]   # test-without-building
#   scripts/integration-test.sh build                 # build only, no emulator
#   scripts/integration-test.sh test -only-testing:TandemKitIntegrationTests/PairingIntegrationTests
#
# Environment:
#   FAKETANDEM_DIR    faketandem checkout (default: ../faketandem next to this repo).
#   FAKETANDEM_JAR    pumpX2 cliparser jar (default: newest
#                     $FAKETANDEM_DIR/third_party/pumpx2-cliparser-*.jar; `make jar` there fetches it).
#   FAKETANDEM_ARGS   Extra flags for the emulator (e.g. "-q" for info-level logging).
#   FAKETANDEM_HOST   Interface to bind (default 127.0.0.1; the simulator shares the host network).
#   LOG_DIR           Where faketandem.log / xcodebuild.log / the .xcresult go
#                     (default: $DERIVED_DATA/integration-logs).
#   Everything scripts/test-local.sh reads (TRIO_PRODUCTS, DERIVED_DATA, SIMULATOR).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKETANDEM_DIR="${FAKETANDEM_DIR:-$ROOT/../faketandem}"
FAKETANDEM_HOST="${FAKETANDEM_HOST:-127.0.0.1}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derived-data}"
LOG_DIR="${LOG_DIR:-$DERIVED_DATA/integration-logs}"
export DERIVED_DATA
export SCHEME=TandemKitIntegrationTests

mode="${1:-all}"; shift || true
mkdir -p "$LOG_DIR"

if [[ "$mode" == "build" ]]; then
  exec "$ROOT/scripts/test-local.sh" build "$@"
fi

if [[ ! -f "$FAKETANDEM_DIR/go.mod" ]]; then
  echo "faketandem checkout not found at $FAKETANDEM_DIR; set FAKETANDEM_DIR" >&2
  exit 1
fi
if [[ -z "${FAKETANDEM_JAR:-}" ]]; then
  FAKETANDEM_JAR="$(ls -t "$FAKETANDEM_DIR"/third_party/pumpx2-cliparser-*.jar 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$FAKETANDEM_JAR" || ! -f "$FAKETANDEM_JAR" ]]; then
  echo "pumpX2 cliparser jar not found; run 'make jar' in $FAKETANDEM_DIR or set FAKETANDEM_JAR" >&2
  exit 1
fi
if ! command -v java >/dev/null; then
  echo "java is required for faketandem's JPAKE (pumpX2 jpake-server)" >&2
  exit 1
fi

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("'"$FAKETANDEM_HOST"'",0)); print(s.getsockname()[1]); s.close()'
}

echo "Building faketandem from $FAKETANDEM_DIR"
(cd "$FAKETANDEM_DIR" && go build -o "$LOG_DIR/faketandem" .)

GATT_PORT="$(free_port)"
API_PORT="$(free_port)"
GATT_ADDR="$FAKETANDEM_HOST:$GATT_PORT"
API_URL="http://$FAKETANDEM_HOST:$API_PORT"

# shellcheck disable=SC2206
EXTRA_ARGS=(${FAKETANDEM_ARGS:-})
"$LOG_DIR/faketandem" -transport virtual -virtual-addr "$GATT_ADDR" -api-addr "$FAKETANDEM_HOST:$API_PORT" \
  -pumpx2-jar-path "$FAKETANDEM_JAR" "${EXTRA_ARGS[@]}" > "$LOG_DIR/faketandem.log" 2>&1 &
FAKETANDEM_PID=$!

cleanup() {
  if kill -0 "$FAKETANDEM_PID" 2>/dev/null; then
    kill "$FAKETANDEM_PID" 2>/dev/null || true
    wait "$FAKETANDEM_PID" 2>/dev/null || true
  fi
  echo "faketandem log: $LOG_DIR/faketandem.log"
  echo "xcodebuild log: $LOG_DIR/xcodebuild.log"
}
trap cleanup EXIT

echo "faketandem pid $FAKETANDEM_PID; GATT $GATT_ADDR; API $API_URL"
for _ in $(seq 1 120); do
  if curl -sf "$API_URL/api/bluetooth/pairingstate" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$FAKETANDEM_PID" 2>/dev/null; then
    echo "faketandem exited during startup; see $LOG_DIR/faketandem.log" >&2
    tail -n 30 "$LOG_DIR/faketandem.log" >&2
    exit 1
  fi
  sleep 0.5
done
if ! curl -sf "$API_URL/api/bluetooth/pairingstate" >/dev/null 2>&1; then
  echo "faketandem API did not come up on $API_URL" >&2
  exit 1
fi

# xcodebuild strips the TEST_RUNNER_ prefix and hands the rest to the test process.
export TEST_RUNNER_FAKETANDEM_GATT="$GATT_ADDR"
export TEST_RUNNER_FAKETANDEM_API_URL="$API_URL"

RESULT_BUNDLE="$LOG_DIR/TandemKitIntegrationTests.xcresult"
rm -rf "$RESULT_BUNDLE"

set +e
"$ROOT/scripts/test-local.sh" "$mode" -resultBundlePath "$RESULT_BUNDLE" "$@" 2>&1 | tee "$LOG_DIR/xcodebuild.log"
status=${PIPESTATUS[0]}
set -e
echo "result bundle: $RESULT_BUNDLE"
exit "$status"
